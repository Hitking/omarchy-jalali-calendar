# تقویم شمسی برای اُمارچی

**تقویم جلالی (هجری شمسی) در نوار اُمارچی.** یک نمای ماهانه با رویدادهای واقعی
شما روی آن، و نواری که پیش از شروع هر جلسه به شما می‌گوید چه چیزی در راه است.

با یک کلیک بین **شمسی و میلادی** سوییچ می‌کند، پس لازم نیست ساعت داخلی اُمارچی
را کنارش نگه دارید — این افزونه جایش را کامل می‌گیرد. فونت **وزیرمتن** همراه
خودش است و نیازی به نصب جداگانه ندارد.

رویدادها از **گوگل کلندر** یا هر سرور **CalDAV** می‌آیند: SmarterMail،
Nextcloud، Radicale، Fastmail، iCloud.

این افزونه فورکی است از
[tmn73/omarchy-calendar](https://github.com/tmn73/omarchy-calendar) که خودش
فورکی از ساعت داخلی اُمارچی است.

*A Jalali (Solar Hijri) calendar for the Omarchy bar — see
[English](#english) below.*

## چه چیزی عوض شده

| | تقویم اصلی | این افزونه |
|---|---|---|
| تقویم | فقط میلادی | **شمسی یا میلادی**، با یک کلیک |
| فونت | فونت نوار | **وزیرمتن، همراه افزونه** |
| منبع رویداد | فقط گوگل | **گوگل یا هر CalDAV** (SmarterMail و…) |
| سال تولد | میلادی | در تقویم فعال، ذخیره به میلادی |

آنچه عوض **نشده** فایل رویدادهاست. کلید هر روز همچنان `YYYY-MM-DD` میلادی است،
یعنی همان فایلی که تقویم اصلی می‌خوانَد. پس یک همگام‌سازی برای هر دو افزونه کافی
است و اگر قبلاً تقویم اصلی را راه انداخته‌اید، لازم نیست دوباره چیزی تنظیم کنید.

## سوییچ بین شمسی و میلادی

پنل را باز کنید، چرخ‌دنده، بخش **تقویم**، و یکی از دو دکمه را بزنید. یا از خط
فرمان:

```bash
omarchy shell jalali-calendar toggleCalendar
omarchy shell jalali-calendar setCalendar gregorian
```

سوییچ فقط نام ماه‌ها را عوض نمی‌کند. هر چیزی که باید با تقویم عوض شود، می‌شود:

| | شمسی | میلادی |
|---|---|---|
| شروع هفته | شنبه | دوشنبه |
| تعطیلی | جمعه (پنجشنبه اختیاری) | شنبه و یکشنبه |
| شمارهٔ هفته | از نوروز، شنبه تا جمعه | ISO 8601 |
| ارقام | فارسی | لاتین |
| چیدمان | راست‌به‌چپ | چپ‌به‌راست |
| زبان رابط | فارسی | انگلیسی |
| نام ماه‌ها | فارسی | از locale خود سیستم |
| نوار پیشرفت سال | در نوروز خالی می‌شود | در ژانویه |
| قالب‌های راست‌کلیک | `yyyy/MM/dd` | `yyyy-MM-dd`، `'W'ww` |

چون یک تقویم شمسی که هفته‌اش از دوشنبه شروع شود و هفته‌هایش را ISO بشمارد،
یک تقویم میلادی است با اسم‌های فارسی.

هر کدام از این‌ها را جداگانه هم می‌شود تغییر داد، و انتخاب صریح شما بعد از
سوییچ هم سر جایش می‌ماند — چیزی که عمداً انتخاب کرده‌اید را یک دکمهٔ نمایش
پس نمی‌گیرد.

**آنچه سوییچ عوض نمی‌کند رویدادهاست.** کلید هر روز در فایل رویدادها میلادی است
و میلادی می‌ماند، پس عوض‌کردن تقویم حتی یک رویداد را هم جابه‌جا نمی‌کند. تستی
هست که دو جدول را کنار هم می‌گذارد و همین را ثابت می‌کند.

## پیش‌نیازها

اُمارچی ۴ با Quickshell. **فونت وزیرمتن همراه خود افزونه است** و لازم نیست
نصبش کنید. (اگر جای دیگری هم لازمش دارید، نام پکیج در AUR `vazirmatn-fonts`
است — نه `ttf-vazirmatn` که وجود ندارد.)

## نصب

```bash
omarchy plugin add https://gitea.qalam.group/masoud/omarchy-jalali-calendar.git --enable
```

یا از روی یک کلون محلی:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/masoud.jalali-calendar
omarchy plugin enable masoud.jalali-calendar
```

این افزونه **جای ساعت داخلی را می‌گیرد**. در `~/.config/omarchy/shell.json`
مدخل `omarchy.clock` را از `bar.layout.center` بردارید و `bar.centerAnchor` را
به این افزونه بدهید:

```json
{
  "bar": {
    "centerAnchor": "masoud.jalali-calendar",
    "layout": {
      "center": [
        { "id": "masoud.jalali-calendar", "format": "dddd HH:mm" }
      ]
    }
  }
}
```

سپس:

```bash
omarchy restart shell
```

**نصب، تمام کار نیست.** تا اینجا یک ساعت کار می‌کند و یک تقویم خالی، چون هنوز
چیزی به آن خوراک نمی‌دهد. پایین‌تر گوگل کلندر را وصل کنید، یا هر منبع دیگری را
به فایل رویدادها وصل کنید. خود پنل هم وقتی بازش کنید همین را با دستورش می‌گوید.

## قالب‌های تاریخ

نشانه‌های Qt، ولی روی تقویم جلالی. راست‌کلیک روی ساعت بین قالب‌های آماده
می‌چرخد و انتخابتان را در `shell.json` می‌نویسد.

| نشانه | معنی | نمونه |
|---|---|---|
| `yyyy` / `yy` | سال | `۱۴۰۵` / `۰۵` |
| `MMMM` / `MMM` | نام ماه | `شهریور` |
| `MM` / `M` | شمارهٔ ماه | `۰۶` / `۶` |
| `dddd` / `ddd` | نام روز هفته | `دوشنبه` / `د` |
| `dd` / `d` | روز ماه | `۰۹` / `۹` |
| `HH` / `H` | ساعت ۲۴ساعته | `۱۴` |
| `hh` / `h` + `AP` | ساعت ۱۲ساعته | `۰۲ ب.ظ` |
| `mm` / `ss` | دقیقه / ثانیه | `۰۵` |
| `ww` / `w` | هفتهٔ سال | `۲۴` |
| `'…'` | متن عینی | `'هفته'ww` → `هفته۲۴` |

ماه‌های فارسی کوته‌نوشت پذیرفته‌ای ندارند، پس `MMM` همان `MMMM` است.

## کلیدها و کلیک‌ها

| | |
|---|---|
| کلیک چپ روی ساعت | باز و بستن تقویم |
| کلیک راست | چرخیدن بین قالب‌های تاریخ |
| کلیک وسط | منوی منطقهٔ زمانی |
| `←` `→` | ماه قبل / بعد (در چیدمان راست‌به‌چپ برعکس) |
| `↑` `↓` | سال قبل / بعد |
| `[` `]` `{` `}` | ماه و سال، مستقل از جهت چیدمان |
| `t` | برگشت به امروز |
| `w` | تغییر روز شروع هفته |
| چرخ ماوس روی جدول | ماه بعد و قبل |
| دوبار کلیک روی نوار سال | تنظیم سال تولد (نوار «یادِ مرگ») |

## تنظیمات

روی ساعت کلیک کنید، بعد آیکن چرخ‌دنده در سر پنل.

| بخش | کار |
|---|---|
| تقویم‌ها | نمایش یا پنهان‌کردن هر تقویم. فهرست از خودِ رویدادهای شما ساخته می‌شود |
| شروع هفته از شنبه | خاموش یعنی هفته از دوشنبه شروع می‌شود |
| پنجشنبه هم تعطیل است | جمعه همیشه تعطیل است؛ پنجشنبه در ایران واقعاً محل اختلاف است |
| ارقام فارسی | خاموش یعنی `1405` به‌جای `۱۴۰۵` |
| چیدمان راست‌به‌چپ | خاموش یعنی همان چیدمان چپ‌به‌راست تقویم اصلی |
| رویدادهای محل کار | نشانه‌های دورکاری گوگل، پیش‌فرض پنهان |
| دعوت‌های رد شده | روشن یعنی خط‌خورده نمایش داده شوند، خاموش یعنی اصلاً نه |
| نوار سال و زندگی | نوارهای ساعت اصلی، پیش‌فرض خاموش |
| برچسب نوار | چند دقیقه مانده به رویداد، نوار آن را اعلام کند |
| همگام‌سازی | تعداد رویداد، منبع و زمان آخرین همگام‌سازی |

فونت از `shell.json` تنظیم می‌شود، نه از این صفحه — چون یک رشتهٔ آزاد است و
صفحهٔ تنظیمات فقط کلید و دکمه دارد:

```json
{ "id": "masoud.jalali-calendar", "fontFamily": "Vazirmatn" }
```

`Vazirmatn` همان نسخه‌ای است که با افزونه می‌آید (`fonts/`، تحت OFL 1.1) و با
`FontLoader` برای کل پروسهٔ شل ثبت می‌شود، پس روی سیستمی که هیچ فونت فارسی
ندارد هم کار می‌کند. مقدار خالی یعنی همان فونت نوار.

آیکن‌ها همیشه با فونت نوار کشیده می‌شوند، چون هیچ فونت فارسی گلیف‌های Nerd Font
را ندارد.

## همگام‌سازی با SmarterMail (و هر CalDAV دیگر)

```bash
~/.config/omarchy/plugins/masoud.jalali-calendar/sync/setup-caldav
```

سه چیز می‌پرسد و بقیه‌اش را خودش پیدا می‌کند:

1. **آدرس سرور** — برای SmarterMail همان هاستی که وبمیل را رویش باز می‌کنید،
   مثل `https://mail.example.com/`. نه مسیر وبمیل، نه آدرس یک تقویم خاص:
   اسکریپت با PROPFIND از خود سرور می‌پرسد principal و تقویم‌ها کجا هستند.
2. **نام کاربری** — معمولاً آدرس ایمیل کامل.
3. **رمز** — اگر حساب دو مرحله‌ای است، باید **رمز اختصاصی برنامه** بسازید، نه
   رمز حساب. CalDAV راهی برای پرسیدن عامل دوم ندارد.

پیش از آنکه چیزی در کانفیگ بنویسد، وصل می‌شود و تقویم‌ها را فهرست می‌کند. اگر
نشد، هیچ چیز نوشته نمی‌شود.

رمز در `~/.config/omarchy/calendar-caldav.password` با دسترسی `600` ذخیره
می‌شود — نه در خود کانفیگ، چون کانفیگ سر از ریپوی dotfiles درمی‌آورد. اگر
password manager دارید، آن فایل را پاک کنید و `OMARCHY_CALDAV_PASSWORD` را در
محیط سرویس بگذارید.

آنچه پشتیبانی می‌شود: چند تقویم، رنگ هر تقویم، رویدادهای تمام‌روز و چندروزه،
دعوت‌های رد شده (خط‌خورده)، لینک جلسه (Teams، Zoom، Meet، Webex و…)، و
رویدادهای تکرارشونده — `FREQ`، `INTERVAL`، `COUNT`، `UNTIL`، `BYDAY` (با
ترتیب، مثل «دومین سه‌شنبهٔ ماه»)، `BYMONTHDAY`، `BYMONTH`، `EXDATE`، `RDATE`.

نام منطقهٔ زمانی ویندوزی که سرورهای هم‌خانوادهٔ Exchange می‌فرستند — مثل
`Iran Standard Time` — به IANA ترجمه می‌شود.

## همگام‌سازی گوگل کلندر

```bash
~/.config/omarchy/plugins/masoud.jalali-calendar/sync/setup
```

اسکریپت همگام‌سازی دست‌نخورده از تقویم اصلی آمده و همان فایل و همان تایمر
systemd را می‌سازد. **اگر قبلاً برای تقویم اصلی اجرایش کرده‌اید، دوباره لازم
نیست.** جزئیات کامل — چهار مرحله‌ای که باید دستی در Google Cloud Console انجام
شود و دو تلهٔ آن — در
[README تقویم اصلی](https://github.com/tmn73/omarchy-calendar#sync-your-google-calendar)
آمده است.

## منبع دیگری غیر از این دو

ویجت اصلاً نمی‌داند گوگل یا SmarterMail وجود دارند. یک فایل می‌خواند و رسمش
می‌کند:

```
~/.local/state/omarchy/calendar-events.json
```

هر چیزی که این فایل را بنویسد کار می‌کند: khal، vdirsyncer، Nextcloud، یک فید
ICS، یا یک اسکریپت شل. قالب دقیقاً همان قالب تقویم اصلی است — از جمله اینکه
`dateKey` **میلادی** است، نه شمسی. تبدیل به شمسی کار این افزونه است، نه کار
نویسندهٔ فایل. قرارداد کامل در
[README تقویم اصلی](https://github.com/tmn73/omarchy-calendar#use-another-source).

## تعطیلات رسمی

فعلاً نه. تعطیلات ایران هم قمری‌اند و هم شمسی و بعضی‌شان تا نزدیک روز موعود
اعلام نمی‌شوند، یعنی به یک جدول سالانه نیاز دارند نه یک فرمول. آنچه اینجا هست
فقط جمعه (و اختیاراً پنجشنبه) است، که یک قاعده است و می‌شود به آن اعتماد کرد.

## بردنش روی یک ماشین دیگر

[`docs/PUBLISHING.md`](docs/PUBLISHING.md) کل مسیر را دارد: گرفتن ریپو، نصب
افزونه از روی URL (نه از مسیر محلی، وگرنه `omarchy plugin update` مبدأش را گم
می‌کند)، پوش دوباره به Gitea یا گیت‌هاب، و چرخهٔ توسعه روی افزونه‌ای که نصب شده.

## توسعه

```bash
node --test tests/*.test.js
cd sync && PYTHONPATH=. python3 -m unittest discover -s ../tests -t ..
```

بدون هیچ وابستگی، در هر دو طرف. تمام حساب تاریخ در `Model.js` است که زیر node
هم بار می‌شود، دقیقاً برای همین که بشود تستش کرد. تبدیل تقویم الگوریتم ۳۳سالهٔ
بورکوفسکی است — همان که `jalaali-js` پیاده می‌کند — و برای سال‌های ۱۱۷۸ تا
۱۶۳۳ شمسی دقیق است. تست‌ها هر روزِ ۲۰۰ سال را در هر دو جهت تبدیل می‌کنند.

سمت پایتون هم فقط کتابخانهٔ استاندارد است: خوانندهٔ iCalendar، بسط قواعد تکرار
و کلاینت CalDAV همه دستی نوشته شده‌اند. یک تایمر systemd که وابستگی pip دارد،
تایمری است که با اولین ارتقای پایتون می‌شکند و تقویم بی‌صدا از کار می‌افتد.

`Model.js` عمداً یک فایل است: QML به یک فایل `.js` وارد‌شده اجازه نمی‌دهد فایل
دیگری را طوری import کند که node هم بتواند بارش کند.

`Panel.qml` و `BarWidget.qml` تست واحد ندارند: ویجت‌های Quickshell برای رندر
شدن به یک شل زنده نیاز دارند و ساختن آن هارنس بیشتر از چیزی که می‌گیرد
هزینه دارد.

---

<a name="english"></a>

## English

A Jalali (Solar Hijri) calendar and clock for the Omarchy bar — a fork of
[tmn73/omarchy-calendar](https://github.com/tmn73/omarchy-calendar), itself a
fork of Omarchy's built-in clock.

Everything the upstream calendar does, done against the Jalali calendar: month
names, week numbers counted from Nowruz, Saturday-start weeks, Friday
weekends, Persian digits and a right-to-left layout.

**It switches.** One setting turns the whole widget Gregorian -- ISO week
numbers, Monday-start weeks, Latin digits, English labels, month names from
your own locale, the built-in clock's format ring -- so it replaces Omarchy's
clock outright rather than sitting beside it. A Jalali calendar opening its
weeks on Monday and numbering them ISO would be a Gregorian calendar wearing
Persian names, so the calendar carries all of that with it; each piece stays
overridable, and an explicit choice survives a later switch.

```bash
omarchy shell jalali-calendar toggleCalendar
omarchy shell jalali-calendar setCalendar gregorian
```

**Vazirmatn ships with the plugin** under OFL 1.1 and is registered through
`FontLoader`, so it works on a machine with no Persian font installed. Icons
are always drawn in the bar's own font, because no Persian face carries Nerd
Font glyphs.

**Events come from Google Calendar or any CalDAV server** -- SmarterMail,
Nextcloud, Radicale, Fastmail, iCloud. The CalDAV client does its own
discovery, expands recurrence rules, and translates the Windows timezone
names Exchange-lineage servers emit. Standard library only, like the rest of
the sync.

```bash
sync/setup          # Google Calendar
sync/setup-caldav   # SmarterMail and every other CalDAV server
```

The one thing deliberately left alone is the data contract. Events are still
read from `~/.local/state/omarchy/calendar-events.json`, still keyed by
Gregorian `YYYY-MM-DD`, so any sync written for the upstream calendar feeds
this one unchanged and both plugins can share a single timer. Switching the
displayed calendar cannot move an event by so much as a day, and there is a
test holding one grid against the other to prove it: a calendar is a way of
naming a day, never the day itself.

```bash
omarchy plugin add https://gitea.qalam.group/masoud/omarchy-jalali-calendar.git --enable
```

Then point `bar.centerAnchor` at `masoud.jalali-calendar` in
`~/.config/omarchy/shell.json`, remove `omarchy.clock` from
`bar.layout.center`, and `omarchy restart shell`.

Format tokens are Qt's, resolved against whichever calendar is active:
`yyyy MMMM dddd d HH mm ww`, with `'…'` for literals.

## License

MIT. Derived from Omarchy's built-in clock plugin by way of
tmn73/omarchy-calendar, whose copyright notices are kept in `LICENSE`.
