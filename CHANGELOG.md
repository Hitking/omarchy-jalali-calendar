# تغییرات / Changelog

## 0.4.1 — ۵ مهر ۱۴۰۵ / 2026-09-27

**برای کاربران**

- امروز در جدول دوباره فقط یک قاب دورِ عدد دارد؛ خانهٔ پُررنگِ ۰٫۴٫۰ بیش از
  حد به چشم می‌آمد. دکمهٔ «امروز» سر جایش است.

**For reviewers**

- Panel: today's grid cell is outlined again instead of filled (reverts that
  part of 0.4.0); the day number keeps the normal colour and stays bold.

## 0.4.0 — ۵ مهر ۱۴۰۵ / 2026-09-27

**برای کاربران**

- دکمهٔ «امروز»: کنار نام ماه، زیر جدول. هر جا که رفته باشید، با یک کلیک به
  امروز برمی‌گردید. کلید `t` و کلیک روی تاریخ بزرگ بالای پنل هم همین کار را
  می‌کنند.
- امروز در جدول حالا یک خانهٔ پُررنگ است و از دور پیدا می‌شود.
- اگر روزی از سال دیگری انتخاب شده باشد، عنوان رویدادها سال را هم می‌نویسد.
  پیش‌تر مثلاً «دوشنبه ۵ مهر» (یعنی ۱۴۰۶) طوری دیده می‌شد که انگار امروز است
  و روز هفته‌اش اشتباه است.
- اتصال به CalDAV امن‌تر شد: رمز فقط به همان سروری که وارد کرده‌اید فرستاده
  می‌شود و پاسخ‌های غیرعادی بزرگ سرور، همگام‌سازی را از کار نمی‌اندازد.
- وصل کردن حساب از تنظیمات دیگر پنل را وسط کار از نو بارگذاری نمی‌کند؛
  رویدادها بلافاصله دیده می‌شوند.
- راهنما دستور آماده‌ای برای برداشتن ساعت پیش‌فرض اُمارچی از نوار دارد.

**For reviewers**

- Panel: a "Today" button resets both the visible month and the selected
  day; today's grid cell is filled instead of outlined; the agenda heading
  shows the year when the selected day is outside the current year.
- CalDAV sync: Basic credentials are only sent to the origin the user
  entered (redirects and hrefs to other hosts are refused; http→https on the
  same host is allowed). Response bodies are read with per-request size caps
  and a deadline, and DTDs are rejected.
- The sync wrappers write Python bytecode to the user's cache directory
  instead of the plugin folder, which the shell watches and reloads on.
- No new permissions, dependencies or network destinations. Tests:
  `node --test tests/*.test.js` and the Python suite in the README.
