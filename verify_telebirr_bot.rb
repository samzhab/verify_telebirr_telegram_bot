# frozen_string_literal: true

require 'telegram/bot'
require 'dotenv/load'
require 'httparty'
require 'logger'
require 'byebug'
require 'yaml'
require 'date'
require 'vonage'
require 'rqrcode'
require 'gemini-ai'
require 'rtesseract'
require 'open-uri'
# Module for helper methods
module BotHelpers
  def self.validate_presence(values, names)
    Array(values).zip(Array(names)).each do |value, name|
      raise ArgumentError, "Invalid or missing #{name}" if value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end

# Module for Error handling
module ErrorHandler
  def handle_error(error, context = 'General')
    error_message = "#{context}: #{error.message}"
    puts error_message
  end
end

# Helper class to allow Logger to write to multiple outputs
class MultiIO
  def initialize(*targets)
    @targets = targets
  end

  def write(*args)
    @targets.each { |target| target.write(*args) }
  end

  def close
    @targets.each(&:close)
  end
end

# Set up the logger
LOG_FILE = File.join('logs', "#{Time.now.to_s.split[0]}bot_log.log")
LOGGER = Logger.new(MultiIO.new(File.open(LOG_FILE, 'a'), $stdout), 'daily')
LOGGER.formatter = proc do |severity, datetime, _progname, msg|
  "#{datetime}: #{severity} -- #{msg}\n"
end

# Define the User class here
# Represents a user of the Telegram bot.
class User
  attr_accessor :user_id, :username, :api_use_left

  # Initializes a new User object.
  def initialize(user_id, username, api_use_left)
    @user_id = user_id
    @username = username
    @api_use_left = api_use_left
  end
end

# The VerifyTelebirrBot class represents a Telegram bot used for verifying Telebirr transactions.
# It includes various methods for handling user interactions, processing messages, and performing OCR on images.
# rubocop:disable Metrics/ClassLength,Lint/MissingCopEnableDirective
# ...
class VerifyTelebirrBot # rubocop:disable Metrics/ClassLength,Style/Documentation
  include BotHelpers # This mixes in BotHelpers methods as instance methods
  include ErrorHandler
  extend ErrorHandler

  class << self
    def load_ui_strings
      file_path = 'data/ui_strings.yml'
      if File.exist?(file_path)
        YAML.load_file(file_path)
      else
        error_message = "Error: UI strings file not found at #{file_path}"
        handle_error(RuntimeError.new(error_message), 'load_ui_strings')
        {}
      end
    end

    def initialize_gemini_ai_client
      # With an API key
      Gemini.new(
        credentials: {
          service: 'generative-language-api',
          api_key: ENV['GOOGLE_API_KEY']
        },
        options: { model: 'gemini-pro', server_sent_events: true }
      )
    end

    def run(token)
      @created_channels = []
      BotHelpers.validate_presence(token, 'token')
      bot_instance = new # Create an instance of MyTelegramBot
      Telegram::Bot::Client.run(token) do |bot|
        bot_instance.bot_listen(bot) # Call instance method 'bot_listen' on the created instance
      end
    rescue StandardError => e
      handle_error(e, 'run') # Assuming handle_error is correctly defined to handle such errors
    end
    # end of class methods
  end

  UI_STRINGS = load_ui_strings
  GEMINI_AI = initialize_gemini_ai_client
  def bot_listen(bot) # rubocop:disable Metrics/MethodLength
    puts '-----------------------------------------------------------------'
    bot.listen do |update|
      LOGGER.info("Received update: #{update.to_json}")
      cleanup_working_directory
      case update
      when Telegram::Bot::Types::Message
        if update.photo
          respond_to_image(bot, update)
        else
          respond_to_message(bot, update)
        end
      when Telegram::Bot::Types::CallbackQuery
        handle_callback_query(bot, update)
      end
    end
  end

  def rename_old_data_file # rubocop:disable Metrics/MethodLength
    data_files = Dir['data/data*.yaml']

    data_files.each do |file| # rubocop:disable Lint/UnreachableLoop
      new_filename = "data/data#{Time.now.to_s.split[0]}.yaml"
      begin
        File.rename(file, new_filename)
        puts "Successfully renamed #{file} to #{new_filename}"
      rescue Errno::ENOENT
        puts "Error: File #{file} not found. Skipping rename."
      end
      break
    end
  end

  def respond_to_image(bot, update) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    LOGGER.info("Responding to photo message from user #{update.from.id}")
    text = extract_text_from_image(bot, update)

    if text.match?(/Successful/)
      telebirr_transaction = extract_transaction_details(text)
      LOGGER.info("Updating verification code entries from transaction code from photo message from user #{update.from.id}")
      handle_verification(bot, update, telebirr_transaction)
      LOGGER.info("Responding to photo message from user #{update.from.id} with OCR extracted text: #{telebirr_transaction}")
      bot.api.send_message(chat_id: update.chat.id, text: "Extracted text reads: #{telebirr_transaction}")
    else
      LOGGER.info("Responding to photo message from user #{update.from.id} with OCR extracted text doesn't contain key terms: #{text}")
      bot.api.send_message(chat_id: update.chat.id, text: "Extracted text reads: #{text}")
    end
  end

  def extract_text_from_image(bot, update)
    LOGGER.info("Extracting text from photo message from user #{update.from.id}")
    photo = update.photo.last
    file = bot.api.get_file(file_id: photo.file_id)
    image_path = "telebirr_confirmations/#{Time.now}_downloaded_image.jpg"
    file_path = "https://api.telegram.org/file/bot#{ENV['TELEGRAM_BOT_TOKEN']}/#{file.file_path}"
    download_photo(file_path, image_path)
    image_text = RTesseract.new(image_path)
    image_text.to_s
  end

  def respond_to_message(bot, message)
    LOGGER.info("Responding to message from user #{message.from.id}: '#{message.text}'")
    BotHelpers.validate_presence([bot, message], %w[bot message])
    command = extract_command(message.text)
    handle_command(bot, message, command) if command
  rescue ArgumentError, StandardError => e # rubocop:disable Lint/ShadowedException
    LOGGER.error("#{e.class} - respond_to_message: #{e.message}")
    handle_error(e, "#{e.class} - respond_to_message")
  end

  private

  def extract_transaction_details(text) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    lines = text.split
    currency_pattern = /\((ETB|USD|EUR|RUB|GBP|CAD|INR|KRW|BRL|ZAR)\)/
    currency = lines.find { |word| word.match?(currency_pattern) }&.gsub('(', '')&.gsub(')', '') || 'ETB'
    amount = lines.find { |word| word.match?(/\d+\.\d{2}$/) }&.gsub('-', '')&.gsub('—', '') || ''
    { 'status' => lines.find { |word| word == 'Successful' },
      'amount' => amount,
      'currency' => currency,
      'date' => lines.find { |word| word.match?(%r{\d{4}/\d{2}/\d{2}}) },
      'time' => lines.find { |word| word.match?(/\d{2}:\d{2}:\d{2}/) },
      'code' => lines.find { |word| word.match?(/[A-Z0-9]{10}/) } }
  end

  def handle_verification(bot, update, telebirr_transaction)
    verification_code = ['/verify', telebirr_transaction['code']]
    if update.chat.type == 'private'
      handle_private_verification(bot, update, verification_code)
    else
      handle_group_verification(bot, update, verification_code)
    end
  end

  def download_photo(file_path, image_path)
    uri = URI.parse(file_path)
    response = Net::HTTP.get_response(uri)
    File.open(image_path, 'wb') { |file| file.write(response.body) }
  end

  def handle_command(bot, message, command) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength
    case command.first
    when '/link1', '/link2', '/ent', '/del', '/dat', '/set'
      handle_ops_setting(bot, message, command)
    when '/ver'
      handle_ops_setting(bot, message, command)
    when '/start', '/help', '/start@verify_telebirr_telegram_bot', '/help@verify_telebirr_telegram_bot'
      send_helpful_message(bot, message)
    when '/verify', '/verify@verify_telebirr_telegram_bot'
      verify_telebirr_payment(bot, message, command)
    when '/booking', '/booking@verify_telebirr_telegram_bot'
      send_webapp_booking(bot, message, 'https://t.me/verify_telebirr_telegram_bot/hotel_booking')
    when '/ticket', '/ticket@verify_telebirr_telegram_bot'
      send_data_with_buttons(bot, message)
    when '/invoice', '/invoice@verify_telebirr_telegram_bot'
      send_under_construction_message(bot, message)
    when '/privacy_eng', '/privacy_eng@verify_telebirr_telegram_bot'
      send_privacy_message_english(bot, message)
    when '/privacy_amh', '/privacy_amh@verify_telebirr_telegram_bot'
      send_privacy_message_amharic(bot, message)
    when '/terms_eng', '/terms_eng@verify_telebirr_telegram_bot'
      send_terms_english_message(bot, message)
    when '/terms_amh', '/terms_amh@verify_telebirr_telegram_bot'
      send_terms_amharic_message(bot, message)
    else
      send_gemini_ai_message(bot, message)
    end
  end

  def handle_ops_setting(bot, message, command) # rubocop:disable Metrics/MethodLength
    data = load_data
    case command.first
    when '/link1', '/link2'
      set_link(bot, message, command.first.sub('/', ''), command.last, data)
    when '/ent'
      update_schedule(bot, message, command)
    when '/del'
      update_schedule(bot, message, command)
    when '/ver'
      bulk_telebirr_codes(bot, message, command)
    when '/dat'
      export_stored_data(bot, message)
    when '/set'
      reset_stored_data(bot, message)
    end
  end

  def extract_command(text)
    # Regular expression to extract the command, link, username (optional), day (optional), and time (optional)
    # command = text.match(/^\/(set\d|upd|del)\s+(?:(t\.me\/\S+)|(\w+))(?:\s+(\w+)(?:\s+(\d{4})))?/)
    return text unless text != '' && !text.nil?

    text&.split
  end

  def load_data
    # Find YAML file starting with "data" and having ".yml" or ".yaml" extension
    yaml_file = Dir.glob('data/data*.yaml').first || Dir.glob('data/data*.yml').first

    if yaml_file
      # Load YAML file
      LOGGER.info("Opening YAML file #{yaml_file}")
      YAML.load_file(yaml_file)
    else
      # Handle case when no matching file is found
      LOGGER.error("No YAML file starting with 'data' found.")
      {}
    end
  end

  def set_link(bot, message, key, link, data) # rubocop:disable Metrics/AbcSize
    # Add the links, schedule entry, telebirr_paid_codes, verification_codes
    # and booked_events to yaml datafile data/data#{Time.now.to_s.split[0]}.yaml file
    data['link1'] ||= []
    data['link2'] ||= []
    data[key] = link
    data['schedule'] ||= [] # Add the schedule entry to the data/data#{Time.now.to_s.split[0]}.yaml file
    data['telebirr_paid_codes'] ||= []
    data['verification_codes'] ||= []
    data['booked_events'] ||= []
    File.open("data/data#{Time.now.to_s.split[0]}.yaml", 'w') { |file| file.write(data.to_yaml) }
    bot.api.send_message(chat_id: message.chat.id, text: "#{key.capitalize} set to: #{link}")
  end

  def cleanup_working_directory
    LOGGER.info('Cleaning up working directory...')
    rename_old_data_file
    # Delete all image files
    Dir.glob('telebirr_confirmations/*').each do |image_file|
      File.delete(image_file)
    end

    # Delete all gemini api usage data apart from the latest
    return unless latest_gemini_file

    new_name = "gemini_#{Time.now.strftime('%Y_%m_%d')}.data"
    File.rename(latest_gemini_file, new_name)
  end

  def export_stored_data(bot, message) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
    LOGGER.info('Exporting data files...')
    # Find all YAML files matching the pattern "data/data*.yaml" or "data*.yml"
    files_to_send = Dir.glob('data/data*.yaml') + Dir.glob('data*.yml')
    if files_to_send.any?
      files_to_send.each do |file_path|
        # Read the content of each file
        file_content = File.read(file_path)
        # Find YAML file starting with "data" and having ".yml" or ".yaml" extension
        Dir.glob('data/data*.yaml').first || Dir.glob('data/data*.yml').first
        data = load_data
        # Convert data to a formatted message
        formatted_message = (UI_STRINGS['export_message']).to_s
        data.each do |key, value|
          formatted_message += "#{key}:\n"
          if value.is_a?(Array)
            value.each_with_index do |item, index|
              formatted_message += "  #{index + 1}. #{item}\n"
            end
          elsif value.is_a?(Hash)
            value.each do |k, v|
              formatted_message += "  #{k}: #{v}\n"
            end
          else
            formatted_message += "  #{value}\n"
          end
        end
        # Send the formatted message
        bot.api.send_message(chat_id: message.chat.id, text: formatted_message)
        # Send the file as a document
        bot.api.send_document(
          chat_id: message.chat.id,
          document: Faraday::UploadIO.new(StringIO.new(file_content), 'application/yaml', File.basename(file_path)),
          caption: "#{UI_STRINGS['export_message']}#{File.basename(file_path)}"
        )
      end
    else
      bot.api.send_message(chat_id: message.chat.id, text: 'No data files found to send.')
    end
  end

  def bulk_telebirr_codes(bot, message, text) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
    LOGGER.info('Processing bulk telebirr codes')

    # Initialize variables
    amount_data = nil
    transaction_code = nil
    # Iterate through the text array to find the relevant data
    text.each_with_index do |word, index|
      if word == 'ETB'
        amount_data = [text[index + 1], text[index + 2]]
      elsif (word.downcase == 'transaction' || word.downcase == 'trans') && text[index + 1] == 'number'
        transaction_code = text[index + 3].chomp('.')
        break
      end
    end
    # Check if both amount and transaction code are found
    if amount_data && transaction_code
      existing_data = {}
      # Load existing data from YAML file
      begin
        yaml_file = Dir.glob("data/data#{Time.now.to_s.split[0]}.yaml") + Dir.glob("data/data#{Time.now.to_s.split[0]}.yaml")
        existing_data = YAML.load_file(yaml_file.first) || {}
        if yaml_file.empty?
          LOGGER.warn("YAML file #{yaml_file} found. But is empty.")
          nil
        else
          # access contents and check if code exists if not add it idempotently
          # Add or update booked_events section with booking_info
          verification_code = { 'trans_no' => transaction_code }
          existing_data['telebirr_paid_codes'] ||= []

          # Store the verification codes idempotently
          if existing_data['telebirr_paid_codes'].any? { |code| code['trans_no'] == transaction_code }
            LOGGER.info("Verification code #{transaction_code} already exists.")
            bot.api.send_message(
              chat_id: message.chat.id,
              text: (UI_STRINGS['telebirr_paid_user_notification']).to_s
            )
          else
            existing_data['telebirr_paid_codes'] << verification_code
            LOGGER.info("Verification code #{transaction_code} stored successfully.")
            bot.api.send_message(
              chat_id: message.chat.id,
              text: "#{transaction_code} - \n#{UI_STRINGS['telebirr_paid_user_notified']}"
            )
            begin
              File.open(yaml_file.first, 'w') { |file| file.write(existing_data.to_yaml) }
              # File.open(yaml_file.first, 'w') { |file| file.write(data.to_yaml) }
              LOGGER.info("1 telebirr code added to data/data#{Time.now.to_s.split[0]}.yaml")
            rescue StandardError => e # rubocop:disable Metrics/BlockNesting
              LOGGER.error("Error writing to YAML file: #{e.class}: #{e.message}")
            end
          end
        end
      rescue StandardError => e
        LOGGER.error("Error loading YAML file: #{e.class}: #{e.message}")
        nil
      end
    else
      LOGGER.error('Failed to extract amount data or transaction code from the provided text.')
      # Handle the case where either amount data or transaction code is not found
      # You can send a message or perform any other action here
    end
  end

  def verify_telebirr_payment(bot, message, verification_code)
    if message.chat.type == 'private'
      handle_private_verification(bot, message, verification_code)
    else
      handle_group_verification(bot, message, verification_code)
    end
  end

  def handle_group_verification(bot, message, verification_code) # rubocop:disable Lint/UnusedMethodArgument
    LOGGER.info((UI_STRINGS['only_private_verification']).to_s)
    bot.api.send_message(chat_id: message.chat.id,
                         text: "#{UI_STRINGS['only_private_verification']}") # rubocop:disable Style/RedundantInterpolation
  rescue StandardError => e
    LOGGER.error("Error sending message #{e.class}: #{e.message}")
  end

  def handle_private_verification(bot, message, verification_code) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/PerceivedComplexity,Metrics/CyclomaticComplexity
    if verification_code.first == '/verify' && !verification_code[1].nil?
      verification_code = verification_code[1]
      LOGGER.info("Verifying telebirr payment with code. - #{verification_code}")
      # Load existing data from YAML file
      begin
        yaml_file = Dir.glob("data/data#{Time.now.to_s.split[0]}.yaml") + Dir.glob("data/data#{Time.now.to_s.split[0]}.yaml")
        existing_data = YAML.load_file(yaml_file.first) || {}
        if yaml_file.empty?
          LOGGER.warn("YAML file #{yaml_file} found. But is empty.")
          nil
        else
          # Ensure 'verification_codes' key exists
          existing_data['verification_codes'] ||= []
          if existing_data['verification_codes'].include?(verification_code)
            LOGGER.info("Verification code #{verification_code} already exists.")
            verified = check_telebirr_paid_codes(existing_data, verification_code)
            if verified # rubocop:disable Metrics/BlockNesting
              link = existing_data['link1']
              qrcode = RQRCode::QRCode.new(verification_code.to_s)
              # Save the QR code image as a PNG file
              # NOTE: showing with default options specified explicitly
              png = qrcode.as_png(
                bit_depth: 1,
                border_modules: 4,
                color_mode: ChunkyPNG::COLOR_GRAYSCALE,
                color: 'black',
                file: nil,
                fill: 'white',
                module_px_size: 6,
                resize_exactly_to: false,
                resize_gte_to: false,
                size: 120
              )
              png.save("qr_codes/qr_code_#{verification_code}.png")
              # Load YAML file containing location information
              locations_data = YAML.load_file('data/locations.yml')
              locations = locations_data['locations']

              # Select a random location
              random_location = locations.sample
              latitude = random_location['latitude']
              longitude = random_location['longitude']

              # Send the file as a document
              qr_code_path = "qr_codes/qr_code_#{verification_code}.png"
              qr_code_file = File.open(qr_code_path, 'rb')

              # Send location and QR code
              bot.api.send_location(
                chat_id: message.chat.id,
                latitude: latitude,
                longitude: longitude
              )
              bot.api.send_photo(
                chat_id: message.chat.id,
                photo: Faraday::UploadIO.new(qr_code_file, 'image/png'),
                caption: "#{UI_STRINGS['payment_verified_info']}\n\n#{link}\n\nScan this QR code to verify payment."
              )
              # bot.api.send_document(
              #   chat_id: message.chat.id,
              #   document: Faraday::UploadIO.new(qr_code_file, 'image/png'),
              #   caption: "Scan this QR code to verify payment."
              # )
              qr_code_file.close
            else
              bot.api.send_message(chat_id: message.chat.id, text: "#{verification_code} - \n "\
                "#{UI_STRINGS['notifed_of_verification']}")
            end
          else
            existing_data['verification_codes'] << verification_code
            File.open("data/data#{Time.now.to_s.split[0]}.yaml", 'w') { |file| file.write(existing_data.to_yaml) }
            LOGGER.info("Verification code #{verification_code} stored successfully.")
            bot.api.send_message(chat_id: message.chat.id,
                                 text: "#{verification_code} - \n#{UI_STRINGS['notify_verification']}")
          end
        end
      rescue StandardError => e
        LOGGER.error("Error loading YAML file: #{e.class}: #{e.message}")
      end
    elsif verification_code.first == '/verify'
      bot.api.send_message(chat_id: message.chat.id, text: (UI_STRINGS['verify_usage_text']))
    end
  end

  def handle_group_verification(bot, message, _verification_code) # rubocop:disable Lint/DuplicateMethods
    # Handle group/channel verification differently
    bot.api.send_message(chat_id: message.chat.id, text: UI_STRINGS['only_private_verification'])
  end

  def check_telebirr_paid_codes(data, verification_code)
    telebirr_paid_codes = data['telebirr_paid_codes']
    telebirr_paid_codes&.any? { |code| code['trans_no'] == verification_code }
  end

  def update_schedule(bot, message, schedule_data)
    data = load_data || {}
    case message.text.downcase
    when %r{/del\s+(.+)}
      handle_removal(bot, message, data)
    else
      handle_update(bot, message, schedule_data, data)
    end
  end

  def handle_removal(bot, message, data) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    removal_term = ::Regexp.last_match(1).strip
    removed_entries = data['schedule'].delete_if do |entry|
      entry['details'].downcase.include?(removal_term.downcase)
    end

    if removed_entries.empty?
      bot.api.send_message(chat_id: message.chat.id,
                           text: "#{UI_STRINGS['no_entries_found_notice']} '#{removal_term}'.")
    else
      data['schedule'] = removed_entries
      save_data(data)
      bot.api.send_message(chat_id: message.chat.id,
                           text: "#{UI_STRINGS['removed_entries_notice']} '#{removal_term}'.")
    end
  end

  def handle_update(bot, message, schedule_data, data) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
    schedule_details = schedule_data[1..3]
    if schedule_details.length != 3
      bot.api.send_message(chat_id: message.chat.id,
                           text: 'Invalid schedule data. Please provide all details: day, time, and event.')
    elsif !valid_time?(schedule_details[2])
      bot.api.send_message(chat_id: message.chat.id,
                           text: 'Invalid time format. Please provide time in four digits between 0000 and 2359.')
    else
      links = { 'link1' => data['link1'], 'link2' => data['link2'] }
      schedule_entry = {
        'details' => schedule_details.join(' '),
        'links' => links
      }
      update_data(bot, message, schedule_details, schedule_entry, data)
    end
  end

  def valid_time?(time)
    time.match?(/\A([01]\d|2[0-3])([0-5]\d)\z/)
  end

  def update_data(bot, message, schedule_details, schedule_entry, data) # rubocop:disable Metrics/AbcSize
    data['schedule'] ||= []
    if data['schedule'].any? { |entry| entry['details'] == schedule_entry['details'] }
      bot.api.send_message(chat_id: message.chat.id,
                           text: "'#{schedule_details}' - \n#{UI_STRINGS['schedule_entry_exists_notice']}")
    else
      data['schedule'] << schedule_entry
      save_data(data)
      bot.api.send_message(chat_id: message.chat.id,
                           text: "#{UI_STRINGS['schedule_updated_with_notice']} '#{schedule_details}'")
    end
  end

  def save_data(data)
    File.open("data/data#{Time.now.to_s.split[0]}.yaml", 'w') { |file| file.write(data.to_yaml) }
  end

  def generate_schedule_keyboard_markup # rubocop:disable Metrics/MethodLength
    data = load_data
    event_names = data['schedule'].map { |entry| entry['details'].split[1] }.uniq
    inline_keyboard_buttons = event_names.map do |event_name|
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: event_name,
        callback_data: 'book_show'
      )
    end
    Telegram::Bot::Types::InlineKeyboardMarkup.new(
      inline_keyboard: inline_keyboard_buttons.each_slice(2).to_a
    )
  end

  def send_data_with_buttons(bot, message) # rubocop:disable Metrics/MethodLength
    begin
      details = load_schedule_details
    rescue StandardError => e
      LOGGER.error("An error occurred: #{e.message}")
      bot.api.send_message(chat_id: message.chat.id, text: (UI_STRINGS['error_loading_data_notice']).to_s)
      details = []
      return
    end

    details.each do |detail|
      send_detail(bot, message, detail)
    end
  end

  def load_schedule_details
    file_to_open = Dir.glob('data/data*.yaml') + Dir.glob('data*.yml')
    raise 'File not found' unless File.exist?(file_to_open.first)

    data = YAML.safe_load(File.read(file_to_open.first))
    details = data['schedule'] || []
    raise 'Content is empty' if details.empty?

    details
  end

  def send_detail(bot, message, detail) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    event_name, day_of_week, time_of_day_string = detail['details'].split(' ')
    parsed_time = parse_time(time_of_day_string)
    message_text = "ተሳታፊ | event: #{event_name}\nቀን | Day: #{day_of_week}\nሰአት | Time: #{parsed_time}"
    options = [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: UI_STRINGS['complete_payment_button'],
        callback_data: 'book_show'
      )
    ]
    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [options])
    bot.api.send_message(chat_id: message.chat.id, text: message_text, reply_markup: markup)
  end

  def parse_time(time_of_day_string)
    begin
      hour = time_of_day_string[0, 2].to_i
      minute = time_of_day_string[2, 2].to_i
      parsed_time = Time.new(2000, 1, 1, hour, minute).strftime('%l:%M %p').strip # rubocop:disable Lint/UselessAssignment
    rescue Date::Error
      puts "Invalid time format: #{time_of_day_string}"
    end

    parsed_time
  end

  def send_webapp_booking(bot, message, webapp_url)
    BotHelpers.validate_presence([bot, message, webapp_url], %w[bot message webapp_url])
    if message.chat.type == 'private'
      handle_private_booking(bot, message, webapp_url)
    else
      handle_group_booking(bot, message)
    end
  rescue StandardError => e
    LOGGER.error("Error in send_webapp_dir: #{e.class}: #{e.message}")
  end

  def handle_group_booking(bot, message)
    LOGGER.info("Informing user #{message.from.id} booking works only in private chat with bot")
    bot.api.send_message(chat_id: message.from.id,
                         text: 'Booking works only in private chat with bot. Send me a private message.')
  end

  def handle_private_booking(bot, message, webapp_url)
    options = {
      reply_markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [
          [Telegram::Bot::Types::InlineKeyboardButton.new(text: UI_STRINGS['open_webapp_button'],
                                                          web_app: { url: webapp_url })]
        ]
      )
    }
    bot.api.send_message(chat_id: message.chat.id,
                         text: UI_STRINGS['booking_info'], **options)
  end

  def clear_screen(chat_id, message_id)
    Telegram::Bot::Client.run(token) do |bot|
      bot.api.delete_message(chat_id: chat_id, message_id: message_id)
    end
  end

  def handle_callback_query(bot, callback_query) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    BotHelpers.validate_presence([bot, callback_query], %w[bot callback_query])
    LOGGER.info("Handling callback query from user #{callback_query.from.id} - #{callback_query.from.username}: '#{callback_query.data}'")
    begin
      case callback_query.data
      when 'confirm_reset'
        delete_data_yaml(bot, callback_query)
      when 'book_show'
        book_show_process(bot, callback_query)
      else ''
      end
    rescue StandardError => e
      LOGGER.error("Error in handle_callback_query: #{e.class}: #{e.message}")
      bot.api.send_message(chat_id: callback_query.from.id,
                           text: UI_STRINGS['request_error_info'])
    end
  end

  def reset_stored_data(bot, message)
    # Send a message to confirm reset
    bot.api.send_message(chat_id: message.chat.id, text: (UI_STRINGS['data_reset_remind']).to_s,
                         reply_markup: confirmation_keyboard)
  end

  def confirmation_keyboard
    # Create a keyboard with a confirm button
    confirm_button = Telegram::Bot::Types::InlineKeyboardButton.new(text: 'አረጋግጥ Confirm',
                                                                    callback_data: 'confirm_reset')
    Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [[confirm_button]])
  end

  def delete_data_yaml(bot, callback_query)
    files_to_delete = Dir.glob('data/data*.yaml') + Dir.glob('data*.yml')

    if files_to_delete.any?
      files_to_delete.each do |file|
        File.delete(file)
      end
      bot.api.send_message(chat_id: callback_query.from.id, text: (UI_STRINGS['data_reset_confirmation']).to_s)
    else
      bot.api.send_message(chat_id: callback_query.from.id, text: 'No data files found to reset.')
    end
  end

  # Generates a random 4-digit confirmation code
  def generate_confirmation_code
    rand(1000..9999)
  end

  # Removes booking records older than 10 minutes
  def remove_old_bookings # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    yaml_file = Dir.glob('data/data*.yaml') + Dir.glob('data*.yml')
    return if yaml_file.empty?

    begin
      existing_data = YAML.load_file(yaml_file.first) || {}
      existing_data['booked_events']&.reject! do |booking|
        Time.now - Time.parse(booking['booking_time']) > 600 # 10 minutes in seconds
      end
      File.open(yaml_file.first, 'w') { |file| file.write(existing_data.to_yaml) }
    rescue StandardError => e
      LOGGER.error("Error removing old bookings: #{e.class}: #{e.message}")
    end
  end

  def book_show_process(bot, callback_query) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
    # Remove old bookings before processing new booking
    remove_old_bookings

    # Extract user ID for private chat
    user_id = callback_query.from.id
    # Initiate private chat (consider replacing with your logic)
    begin
      bot.api.send_message(chat_id: user_id, text: UI_STRINGS['booking_request_info'])
    rescue Telegram::Bot::Exceptions::ChatNotFound => e
      LOGGER.warn("Failed to initiate private chat with user #{user_id}: #{e.message}")
      # Handle chat not found scenario (e.g., inform user to start private chat)
      return
    end
    # Initialize a hash to store the extracted data
    booking_info = {}
    # Extract relevant information from callback message
    callback_query.message.text.split('|').each do |callback_data|
      data = callback_data.strip
      # Use regular expressions to match specific patterns
      if (match = data.match(/event:\s*(.+)/))
        booking_info['event'] = match[1]
      elsif (match = data.match(/Day:\s*(.+)/))
        booking_info['day'] = match[1]
      elsif (match = data.match(/Time:\s*(.+)/))
        booking_info['time'] = match[1]
      end
    end
    booking_info['booking_time'] = Time.now.to_s
    booking_info['booking_code'] = generate_confirmation_code # Generate a random 4-digit confirmation code
    booking_phrase = "The event '#{booking_info['event']}' is scheduled for "\
                     "#{booking_info['day']} at #{Time.parse(booking_info['time']).strftime('%I:%M %p')}."
    # Send Telebirr transfer instructions
    bot.api.send_message(chat_id: user_id, text: "#{booking_phrase}\nI've booked "\
      'this event for you for the next 10 minutes with booking code '\
      "#{booking_info['booking_code']} \n #{UI_STRINGS['complete_payment_info']}")
    # Update YAML file with booking information
    update_yaml_with_booking_info(booking_info)
  end

  def update_yaml_with_booking_info(booking_info) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    # Load existing data from YAML file
    existing_data = {}
    yaml_file = Dir.glob('data/data*.yaml') + Dir.glob('data*.yml')
    if yaml_file.empty?
      LOGGER.warn("YAML file #{yaml_file} found. But is empty.")
      return
    end
    begin
      existing_data = YAML.load_file(yaml_file.first) || {}
    rescue StandardError => e
      LOGGER.error("Error loading YAML file: #{e.class}: #{e.message}")
      return
    end
    # Add or update booked_events section with booking_info
    existing_data['booked_events'] ||= []
    existing_data['booked_events'] << booking_info
    # Write updated data back to YAML file
    begin
      File.open(yaml_file.first, 'w') { |file| file.write(existing_data.to_yaml) }
      LOGGER.info("Booking information added to #{yaml_file}")
    rescue StandardError => e
      LOGGER.error("Error writing to YAML file: #{e.class}: #{e.message}")
    end
  end

  def send_helpful_message(bot, message)
    helpful_message = UI_STRINGS['help_message']
    LOGGER.info("Sending helpful message to user #{message.from.id}")
    bot.api.send_message(chat_id: message.chat.id, text: helpful_message)
    # Check if the message was successfully sent and record its message_id
    # @displayed_messages[message.from.id] = message.message_id
    # @displayed_messages[response.from.id] = response.message_id
  rescue StandardError => e
    LOGGER.error("Error in send_helpful_message: #{e.class}: #{e.message}")
  end

  def send_under_construction_message(bot, message)
    under_construction_message = format(UI_STRINGS['under_construction_message'], first_name: message.from.first_name)
    LOGGER.info("Sending under_construction_message to user #{message.from.id}")
    bot.api.send_message(chat_id: message.chat.id, text: under_construction_message)
  rescue StandardError => e
    LOGGER.error("Error in under_construction_message: #{e.class}: #{e.message}")
  end

  def send_terms_english_message(bot, message)
    terms_of_use_english = UI_STRINGS['terms_of_use_english']
    LOGGER.info("Sending helpful message to user #{message.from.id}")
    bot.api.send_message(chat_id: message.chat.id, text: terms_of_use_english)
  rescue StandardError => e
    LOGGER.error("Error in send_terms_of_use: #{e.class}: #{e.message}")
  end

  def send_terms_amharic_message(bot, message)
    terms_of_use_amharic = UI_STRINGS['terms_of_use_amharic']
    LOGGER.info("Sending helpful message to user #{message.from.id}")
    bot.api.send_message(chat_id: message.chat.id, text: terms_of_use_amharic)
  rescue StandardError => e
    LOGGER.error("Error in send_terms_of_use: #{e.class}: #{e.message}")
  end

  def send_privacy_message_english(bot, message)
    privacy_policy_english = UI_STRINGS['privacy_policy_english']
    LOGGER.info("Sending helpful message to user #{message.from.id}")
    bot.api.send_message(chat_id: message.chat.id, text: privacy_policy_english)
  rescue StandardError => e
    LOGGER.error("Error in send_terms_of_use: #{e.class}: #{e.message}")
  end

  def send_privacy_message_amharic(bot, message)
    privacy_policy_amharic = UI_STRINGS['privacy_policy_amharic']
    LOGGER.info("Sending helpful message to user #{message.from.id}")
    bot.api.send_message(chat_id: message.chat.id, text: privacy_policy_amharic)
  rescue StandardError => e
    LOGGER.error("Error in send_terms_of_use: #{e.class}: #{e.message}")
  end

  def send_gemini_ai_message(bot, message) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
    LOGGER.info("Considering sending Gemini AI Response To User #{message.from.id}")
    # Check if message starts with "Gemini" (case-insensitive)
    if !message.text.downcase.start_with?('gemini')
      LOGGER.info("#{message.from.id} sent a non gemini text. #{message.text}")
      return
    else
      # Load existing data from YAML file
      yaml_file = "#{Time.now.to_s.split[0]}gemini_user_data.yaml"
      existing_data = {}
      if File.exist?(yaml_file)
        begin
          existing_data = YAML.load_file(yaml_file) || {}
        rescue StandardError => e
          LOGGER.error("Error loading YAML file: #{e.class}: #{e.message}")
          return
        end
      end

      user_id = message.from.id.to_s
      user_data = existing_data[user_id]

      # Check if user data exists
      if user_data.nil?
        user_data = {
          'username' => message.from.username,
          'user_id' => message.from.id,
          'last_message_time' => Time.now.to_i,
          'api_calls_left' => 10
        }
        existing_data[user_id] = user_data
      else
        # Check time difference since last message
        last_message_time = Time.at(user_data['last_message_time'])
        time_difference = Time.now - last_message_time
        if time_difference < 120 # 2 minutes in seconds
          LOGGER.warn("#{message.from.id} Please wait 2 minutes before sending another Gemini request. #{message.from.id}")
          bot.api.send_message(chat_id: message.chat.id,
                               text: 'Please wait 2 minutes before sending another Gemini request.')
          return
        else
          user_data['last_message_time'] = Time.now.to_i
          user_data['api_calls_left'] -= 1
        end
      end
    end

    # Process Gemini AI response
    if user_data['api_calls_left'].positive?
      # response = ['Gemini AI response.']
      result = GEMINI_AI.stream_generate_content({ contents: { role: 'user', parts: { text: message.text } } })
      all_texts = result.map { |candidate| candidate['candidates'].first['content']['parts'].first['text'] }
      response = all_texts.join("\n")
      response << "\n\n\n** Hi, #{user_data['username']}, you have #{user_data['api_calls_left']} api uses left for Gemini AI. **"
      LOGGER.info("Sending Gemini AI response: #{response}")
    else
      response = "Hi, #{user_data['username']}, you have no more API uses left for today. You will have 10 more tomorrow.}."
      LOGGER.info("Sending 'no more Gemini AI responses left' message for #{user_data['username']}")
    end
    bot.api.send_message(chat_id: message.chat.id, text: response)
    # Write updated data back to YAML file
    begin
      LOGGER.info("Updating user data in #{yaml_file}")
      File.open(yaml_file, 'w') { |file| file.write(existing_data.to_yaml) }
    rescue StandardError => e
      LOGGER.error("Error writing to YAML file: #{e.class}: #{e.message}")
    end
  end
end

# To Dos
# -to do 1
# -to do 2

# start- ስለ ግላዊ መረጃ አሰባብ ያሳይዎታል | Privacy Policy
# help- ስለ ግላዊ መረጃ አሰባብ ያሳይዎታል | Privacy Policy

# booking - በክፍያ ለማረጋገጥ ከዚህ ይጀምሩ። | Booking for pay and verify.
# ticket - ትኬት / ቀጠሮ ማስያዣ | Generate A Ticket
# verify - የቴሌ ብር ክፍያ ለማረጋገጥ | Verify Your Telebirr Payment
# invoice - ደረሰኝ ለመየቅ | Ask for invoice

# privacy- ስለ ግላዊ መረጃ አሰባብ ያሳይዎታል | Privacy Policy
# terms_amh - ስለ አጠቃቀም ግዴታዎችና መብቶችን ያሳይዎታል። | Terms of Use
# terms_eng - ስለ አጠቃቀም ግዴታዎችና መብቶችን ያሳይዎታል። | Terms of Use

# /link1 t.me/achannelname የቲኬት ሻጭ ድረገፅ ለማስገባት ያምል ፋይሉ ውሰጥ | for entry into yaml file
# /link2 t.me/somelink የቲኬት ሻጭ ድረገፅ ለማስገባት ያምል ፋይሉ ውሰጥ | for entry into yaml file

# /ent Dr.Kiros Friday 1530 ለማስገባት ያምል ፋይሉ ውሰጥ | for entry into yaml file
# /ent Dr.Hana Sunday 1800 for entry into yaml file

# /del monday ለማጥፋት በቀን ከያምል ፋይሉ ውሰጥ | for deletion from yaml file
# /del Dr.Kiros ለማጥፋት በስም ከያምል ፋይሉ ውሰጥ | for deletion from yaml file

# /dat or /set ለዳታ ኤክስፓርትና ማጥፊያ | for data export and reset

# /ver Dear [NAME]
# You have transferred ETB 500.00 to [NAME](phone_number) on [Date]. Your transaction
# number is BCL3GHPES3. The service fee is ETB 0.02. Your current E-Money Account
# balance is ETB 4,333.02. To download your payment information please click this
# link: https://transactioninfo.ethiotelecom.et/receipt/BCL3GHPES3

# /ver Dear [NAME]
# You have received ETB 500.00 from [NAME](phone_number) on {Date}. Your transaction
# number is BCL0H88HN9. Your current E-money Account balance is ETB 1,244.99. Thank you
# for using telebirr Ethio telecom

VerifyTelebirrBot.run(ENV['TELEGRAM_BOT_TOKEN']) if __FILE__ == $PROGRAM_NAME
