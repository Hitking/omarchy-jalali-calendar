# تقویم شمسی برای اُمارچی

**تقویم جلالی (هجری شمسی) در نوار اُمارچی.** یک نمای ماهانه با رویدادهای واقعی
شما روی آن، و نواری که پیش از شروع هر جلسه به شما می‌گوید چه چیزی در راه است.

این افزونه فورکی است از
[tmn73/omarchy-calendar](https://github.com/tmn73/omarchy-calendar) که خودش
فورکی از ساعت داخلی اُمارچی است. تمام حساب تاریخ به تقویم جلالی برگردانده شده،
متن‌ها فارسی شده‌اند، چیدمان راست‌به‌چپ است و فونت پیش‌فرض **وزیرمتن** است.

*A Jalali (Solar Hijri) calendar for the Omarchy bar — see
[English](#english) below.*

## چه چیزی عوض شده

| | تقویم اصلی | این افزونه |
|---|---|---|
| تقویم | میلادی | **جلالی (شمسی)** |
| شروع هفته | یکشنبه/دوشنبه | **شنبه** (قابل تغییر به دوشنبه) |
| تعطیلی | شنبه و یکشنبه | **جمعه** (پنجشنبه اختیاری) |
| شمارهٔ هفته | ISO 8601 | **هفتهٔ سال شمسی**، از نوروز |
| ارقام | لاتین | **فارسی** (قابل تغییر) |
| چیدمان | چپ‌به‌راست | **راست‌به‌چپ** (قابل تغییر) |
| فونت | فونت نوار | **وزیرمتن** (قابل تغییر) |
| نوار پیشرفت سال | سال میلادی | **سال شمسی** — در نوروز خالی می‌شود |
| سال تولد | میلادی | **شمسی**، با پذیرش ارقام فارسی |

آنچه عوض **نشده** فایل رویدادهاست. کلید هر روز همچنان `YYYY-MM-DD` میلادی است،
یعنی همان فایلی که تقویم اصلی می‌خوانَد. پس یک همگام‌سازی برای هر دو افزونه کافی
است و اگر قبلاً تقویم اصلی را راه انداخته‌اید، لازم نیست دوباره چیزی تنظیم کنید.

## پیش‌نیازها

اُمارچی ۴ با Quickshell. فونت وزیرمتن اگر نصب نباشد، fontconfig جایگزینی انتخاب
می‌کند که احتمالاً آن چیزی نیست که می‌خواهید:

```bash
yay -S ttf-vazirmatn        # یا: https://github.com/rastikerdar/vazirmatn
```

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

مقدار خالی یعنی همان فونت نوار. آیکن‌ها همیشه با فونت نوار کشیده می‌شوند، چون
هیچ فونت فارسی گلیف‌های Nerd Font را ندارد.

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

## منبع دیگری غیر از گوگل

این افزونه اصلاً نمی‌داند گوگل وجود دارد. یک فایل می‌خواند و رسمش می‌کند:

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

## توسعه

```bash
node --test tests/*.test.js
cd sync && PYTHONPATH=. python3 -m unittest discover -s ../tests -t ..
```

بدون هیچ وابستگی. تمام حساب تاریخ در `Model.js` است که زیر node هم بار می‌شود،
دقیقاً برای همین که بشود تستش کرد. تبدیل تقویم الگوریتم ۳۳سالهٔ بورکوفسکی است
— همان که `jalaali-js` پیاده می‌کند — و برای سال‌های ۱۱۷۸ تا ۱۶۳۳ شمسی دقیق
است. تست‌ها هر روزِ ۲۰۰ سال را در هر دو جهت تبدیل می‌کنند.

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
weekends, Persian digits, a right-to-left layout, and Vazirmatn as the default
face.

The one thing deliberately left alone is the data contract. Events are still
read from `~/.local/state/omarchy/calendar-events.json`, still keyed by
Gregorian `YYYY-MM-DD`, so any sync written for the upstream calendar feeds
this one unchanged and both plugins can share a single timer. The Jalali date
is a rendering of a day, never its name.

```bash
omarchy plugin add https://gitea.qalam.group/masoud/omarchy-jalali-calendar.git --enable
```

Then point `bar.centerAnchor` at `masoud.jalali-calendar` in
`~/.config/omarchy/shell.json`, remove `omarchy.clock` from
`bar.layout.center`, and `omarchy restart shell`. Install Vazirmatn
(`ttf-vazirmatn`) first, or set `"fontFamily": ""` to inherit the bar's own
face.

Format tokens are Qt's, resolved against the Jalali calendar: `yyyy MMMM dddd
d HH mm ww`, with `'…'` for literals. Icons are always drawn in the bar's
font, because no Persian face carries Nerd Font glyphs.

## License

MIT. Derived from Omarchy's built-in clock plugin by way of
tmn73/omarchy-calendar, whose copyright notices are kept in `LICENSE`.
