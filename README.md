# ቴሌግራም የቴሌብር ክፍያ አረጋጋጭ Bot | Telegram Telebirr Payment Verification Bot

ይህ የቴሌግራም ቦት በደንበኞች እና በአገልግሎት ሰጪወዎች መካከል በግል ቻናል ውስጥ ያለውን ግንኙነት ያመቻቻል። ደንበኞች ስለ ክፍት ቦታዎችና ቲኬቶች መረጃ እንዲጠይቁ፣ ፈጻሚዎችን እንዲመርጡ፣ ክፍያ እንዲፈጽሙ እና በግል ትርኢቶች እንዲዝናኑ ያስችላቸዋል። ✨

This Telegram bot streamlines interactions between customers and service providers within a Telegram group. 🤖 It enables customers to effortlessly request information about tickets, bookings, scheduling, make payments, verify, and enjoy seamless usability. ✨

## ዋና መለያ ጸባያት

- ስለ ሆቴሎች፣ ቱሪስት መስዕቦች፣ ትርኢት እና መርሃ ግብሮቻቸው መረጃ ይሰጣል።
- ደንበኞች እንዲመርጡ እና በክፍያ እንዲቀጥሉ ያስችላቸዋል።
- ደረሰኞችን ይልካል እና የክፍያ ማረጋገጫን ይቆጣጠራል።
- በግል መስመር ውስጥ ከተመዝጋቢዎች ጋር ያወራል፣ ይለጥፋል እና ይገናኛል።
- ለደንበኝነት ተመዝጋቢዎች የግል መልዕክቶችን ይልካል።
- ተጠቃሚዎችን ወደ ቻናሎች/ቡድኖች ያክላል እና ያስወግዳቸዋል።
- ወደ ሌሎች ቻናሎች የግብዣ አገናኞችን ያጋራል።
- ከክፍያ ማረጋገጫ በኋላ የቲኬት ህትመት እና የቦታ ጥቆማ ከደንበኞች ጋር ያካፍላል።

## Features

- Provides information about scheduling, booking, payment, verification and other vital information for telegram users.
- Allows customers to choose an event, or time slot and proceed with payment.
- Sends invoices and handles payment confirmation.
- Posts and interacts with subscribers in telegram groups.
- Sends private messages to subscribers.
- Creates and removes private groups.
- Adds users to groups and removes them.
- Shares invite links to other groups.
- Manages interactions between customers and performer.
- Shares private chat links with customers after payment verification.
- Notifies cam girls when customers arrive and when they are ready to start the show.

## ለመጀመር

1. ማከማቻውን `git clone https://github.com/samzhab/verify_telebirr_telegram_bot.git`

2. ጥገኛዎችን ጫን፡ `bundle install`

3. ከ[@BotFather](https://t.me/BotFather) የቴሌግራም Bot API token ያግኙ።

4. በ`.env` ፋይል ውስጥ `YOUR_BOT_TOKEN`ን በቦት ቶከንዎ ይተኩ።

5. የምዝግብ ማስታወሻዎችን (logs) (data) (telebirr_confirmations) እና የ(qr_codes) አቃፊዎችን (folders) ይፍጠሩ

6. ቦቱን ያሂዱ፡ `ruby verify_telebirr_bot.rb`

7. በቴሌግራም መተግበሪያዎ ውስጥ ከቦት ጋር ይገናኙ።

## Getting Started

1. Clone the repository: `git clone https://github.com/samzhab/verify_telebirr_telegram_bot.git`

2. Install dependencies: `bundle install`

3. Obtain a Telegram Bot API token from [@BotFather](https://t.me/BotFather).

4. Replace `YOUR_BOT_TOKEN` in the `.env` file with your actual bot token.

5. Create logs, data, telebirr_confirmations, and qr_codes folders

6. Run the bot: `ruby verify_telebirr_bot.rb`

7. Interact with the bot in your Telegram app.

##አጠቃቀም
- ቦቱን ይጀምሩ እና ከእሱ ጋር ለመገናኘት ትዕዛዞችን ይላኩ።

## Usage
- Start the bot and send commands to interact with it.

## Admin Commands

### Starting commands (after each reset)
- `/link1 t.me/achannelname` - የቲኬት ሻጭ ድረገፅ ለማስገባት ያምል ፋይሉ ውሰጥ | for entry into yaml file
- `/link2 t.me/somelink` - የቲኬት ሻጭ ድረገፅ ለማስገባት ያምል ፋይሉ ውሰጥ | for entry into yaml file
### Operational commands
- `/ent Dr.Kiros Friday 1530` - ለማስገባት ያምል ፋይሉ ውሰጥ [ስም] [የሳምንት ቀን] እና [የቀኑን ሰዓት] ያክሉ። | Add show [name] [day of week] and [time of day] into yaml file.
- `/ent Dr.Hana Sunday 1800` - ለማስገባት ያምል ፋይሉ ውሰጥ [ስም] [የሳምንት ቀን] እና [የቀኑን ሰዓት] ያክሉ። | Add show [name] [day of week] and [time of day] into yaml file.
### Critical commands
- `/ver TEXT` - Telebirr ለቦት የsms መጣያ ተቀበል። | Telebirr Recieved SMS dump for bot.

- `/ver # Dear [NAME] You have transferred ETB 500.00 to [NAME](phone_number) on [Date]. Your transaction number is BCL3GGBEP3. The service fee is ETB 0.02. Your current E-Money Account balance is ETB 4,333.02. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/BCL3GGBEP3`

- `/ver # Dear [NAME] You have received ETB 500.00 from [NAME](phone_number) on {Date}. Your transaction number is BCL3GGBEP3. Your current E-money Account balance is ETB 9,244.99. Thank you for using telebirr Ethio telecom`

- `/dat` - ለዳታ ኤክስፓርትና ማጥፊያ ውሂብ ወደ ውጭ ይላካል. YAML ፋይል ለማውረድ። | For data export and reset. Exports Data. YAML file for download.
- `/set` - ለዳታ ኤክስፓርትና ማጥፊያ ሁሉንም ውሂብ ዳግም ያስጀምራል። ትኩስ ይጀምራል። | For data export and reset. Resets all data. Starts Fresh.


### Customizations
- `/del monday` - ለማጥፋት በስም ከያምል ፋይሉ ውሰጥ | for deletion from yaml file
- `/del Dr.Kiros` - ለማጥፋት በስም ከያምል ፋይሉ ውሰጥ | for deletion from yaml file


## Bot User Commands
- `/start` - ይሄንን ቦት ለመጀመር | Starts This Bot
- `/help` - የቦቱን ማዘዣዎች ለማየት | Displays Available Commands
- `/booking` - በክፍያ ለማረጋገጥ ከዚህ ይጀምሩ። | Booking for pay and verify
- `/ticket` - ትኬት / ቀጠሮ ማስያዣ | Generate A Ticket
- `/invoice` - ደረሰኝ ለመየቅ | Ask for invoice
- `/verify` - ክፍያ ማረጋገጫ | Bot verifies payment and shares private chat link.
- `/verify BCL0H88HN9` - ክፍያ ማረጋገጫ | Bot verifies payment and shares private chat link
- `/privateterms` - ስለ ስርጭቱ ማሳሰቢያ | Bot informs user of applicable laws and terms.
- `/privacy` - ስለ ግላዊ መረጃ አሰባብ ያሳይዎታል | Privacy Policy
- `/terms` - ስለ አጠቃቀም ግዴታዎችና መብቶችን ያሳይዎታል። | Terms of Use

## ፈቃድ
ይህ ስራ በ[Creative Commons Attribution-ShareAlike 4.0 International License](http://creativecommons.org/licenses/by-sa/4.0/) ስር ፍቃድ ተሰጥቶታል።

![CC BY-SA 4.0](https://i.creativecommons.org/l/by-sa/4.0/88x31.png)

መለያ፡ ይህ ፕሮጀክት በሳማኤል (AI Powered)፣ 2024 ታትሟል።

እርስዎ ለማድረግ ነፃ ነዎት፦
-  አጋራ  - ቁሳቁሱን በማንኛውም መካከለኛ ወይም ቅርጸት ይቅዱ እና እንደገና ያሰራጩ
-  ማላመድ  - ንብረቱን እንደገና ማደባለቅ ፣ መለወጥ እና በማንኛውም ዓላማ ለንግድም ቢሆን መገንባት።
-  አጋራ  - ቁሳቁሱን በማንኛውም መካከለኛ ወይም ቅርጸት ይቅዱ እና እንደገና ያሰራጩ
-  ማላመድ  - ንብረቱን እንደገና ማደባለቅ ፣ መለወጥ እና በማንኛውም ዓላማ ለንግድም ቢሆን መገንባት።

በሚከተለው ውል መሠረት፡-
-  መለያ — ተገቢውን ክሬዲት መስጠት፣ የፍቃዱ አገናኝ ማቅረብ እና ለውጦች መደረጉን መጠቆም አለቦት። በማንኛውም ምክንያታዊ መንገድ ሊያደርጉት ይችላሉ፣ ነገር ግን ፈቃድ ሰጪው እርስዎን ወይም አጠቃቀምዎን እንደሚደግፍ በሚጠቁም በማንኛውም መንገድ አይደለም።
- ሼር አላይክ — ቁሳቁሱን ካዋሃዱ፣ ከቀየሩ፣ ወይም ከገነቡት መዋጮዎን ከመጀመሪያው ባለው ፍቃድ ማሰራጨት አለቦት።

ምንም ተጨማሪ ገደቦች የሉም - ሌሎች ፈቃዱ የሚፈቅደውን ማንኛውንም ነገር እንዳያደርጉ በህጋዊ መንገድ የሚገድቡ ህጋዊ ውሎችን ወይም የቴክኖሎጂ እርምጃዎችን መተግበር አይችሉም።

ማሳሰቢያዎች፡-
በሕዝብ ጎራ ውስጥ ላሉ የቁስ አካላት ወይም አጠቃቀምዎ በሚመለከተው ልዩ ወይም ገደብ የተፈቀደበትን ፈቃድ ማክበር የለብዎትም።

ምንም ዋስትናዎች አልተሰጡም. ፈቃዱ ለታቀደው አገልግሎት አስፈላጊ የሆኑትን ሁሉንም ፈቃዶች ላይሰጥዎት ይችላል። ለምሳሌ፣ እንደ ህዝባዊነት፣ ግላዊነት ወይም የሞራል መብቶች ያሉ ሌሎች መብቶች ቁሱን እንዴት እንደሚጠቀሙ ሊገድቡ ይችላሉ።

## License
This work is licensed under a [Creative Commons Attribution-ShareAlike 4.0 International License](http://creativecommons.org/licenses/by-sa/4.0/).

![CC BY-SA 4.0](https://i.creativecommons.org/l/by-sa/4.0/88x31.png)

Attribution: This project is published by Samael (AI Powered), 2024.

You are free to:
- Share — copy and redistribute the material in any medium or format
- Adapt — remix, transform, and build upon the material for any purpose, even commercially.
Under the following terms:
- Attribution — You must give appropriate credit, provide a link to the license, and indicate if changes were made. You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
- ShareAlike — If you remix, transform, or build upon the material, you must distribute your contributions under the same license as the original.

No additional restrictions — You may not apply legal terms or technological measures that legally restrict others from doing anything the license permits.

Notices:
You do not have to comply with the license for elements of the material in the public domain or where your use is permitted by an applicable exception or limitation.

No warranties are given. The license may not give you all of the permissions necessary for your intended use. For example, other rights such as publicity, privacy, or moral rights may limit how you use the material.
