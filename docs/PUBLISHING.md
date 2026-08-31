# بردن این ریپو روی یک ماشین دیگر، و فرستادنش به گیت

این نوشته برای وقتی است که ریپو را روی کامپیوتر خانه (یا هر ماشین دیگری)
می‌گیرید و می‌خواهید هم افزونه را نصب کنید و هم بتوانید تغییرات را دوباره
به گیت بفرستید.

فرض این نوشته: مبدأ این ریپو Gitea شخصی است روی
`https://gitea.qalam.group/masoud/omarchy-jalali-calendar.git`.

---

## ۱. گرفتن ریپو

```bash
mkdir -p ~/Projects && cd ~/Projects
git clone https://gitea.qalam.group/masoud/omarchy-jalali-calendar.git
cd omarchy-jalali-calendar
```

اگر ریپو **خصوصی** است، گیت نام کاربری و توکن می‌خواهد. یک بار ذخیره‌اش کنید تا
دوباره نپرسد:

```bash
git config --global credential.helper store
```

توکن را از Gitea بسازید: `Settings → Applications → Generate New Token`، با
دسترسی `repository: read/write`. **رمز حساب را ندهید** — توکن قابل ابطال است و
رمز نیست.

## ۲. نصب افزونه روی آن ماشین

اول فونت، وگرنه fontconfig یک جایگزین انتخاب می‌کند که آن چیزی نیست که
می‌خواهید:

```bash
yay -S ttf-vazirmatn
```

بعد افزونه. **از روی URL نصب کنید، نه از روی مسیر محلی:** اُمارچی افزونه را
`git clone` می‌کند و همان `origin` را برای `omarchy plugin update` نگه می‌دارد.
اگر از مسیر محلی نصب کنید، `origin` همان پوشهٔ محلی می‌ماند و به‌روزرسانی از
Gitea دیگر کار نمی‌کند.

```bash
omarchy plugin add https://gitea.qalam.group/masoud/omarchy-jalali-calendar.git
```

سپس در `~/.config/omarchy/shell.json` ساعت داخلی را با این افزونه عوض کنید:

```bash
cp ~/.config/omarchy/shell.json ~/.config/omarchy/shell.json.bak

jq '
  .bar.centerAnchor = "masoud.jalali-calendar"
  | .bar.layout.center = (.bar.layout.center | map(
      if .id == "omarchy.clock" then
        {
          id: "masoud.jalali-calendar",
          format: "dddd HH:mm",
          formatAlt: "dddd d MMMM yyyy",
          verticalFormat: "HH\n—\nmm",
          fontFamily: "Vazirmatn"
        }
      else . end))
' ~/.config/omarchy/shell.json > /tmp/shell.json && mv /tmp/shell.json ~/.config/omarchy/shell.json

omarchy plugin enable masoud.jalali-calendar
omarchy restart shell
```

برگرداندنش هم یک دستور است:

```bash
cp ~/.config/omarchy/shell.json.bak ~/.config/omarchy/shell.json
omarchy plugin remove masoud.jalali-calendar
omarchy restart shell
```

## ۳. فرستادن تغییرات به همان Gitea

ریپویی که کلون کرده‌اید از قبل `origin` دارد، پس چیزی برای تنظیم نیست:

```bash
git add -A
git commit -m "..."
git push
```

اگر `Push to create is not enabled for users` گرفتید، یعنی دارید به ریپویی پوش
می‌کنید که هنوز روی سرور ساخته نشده. Gitea ریپو را با اولین پوش نمی‌سازد؛ اول
باید از `https://gitea.qalam.group/repo/create` بسازیدش، **بدون** README و بدون
هیچ فایل اولیه، وگرنه تاریخچه‌ها واگرا می‌شوند.

از خط فرمان هم می‌شود ساختش:

```bash
curl -X POST https://gitea.qalam.group/api/v1/user/repos \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"omarchy-jalali-calendar","private":true,"default_branch":"main"}'
```

## ۴. فرستادن به گیت‌هاب

اگر خواستید همین ریپو روی گیت‌هاب هم باشد، به‌عنوان ریموت دوم اضافه‌اش کنید.
`origin` را عوض نکنید، وگرنه `omarchy plugin update` مبدأش را گم می‌کند.

```bash
gh auth login                       # مرورگر باز می‌شود؛ HTTPS را انتخاب کنید
gh repo create omarchy-jalali-calendar --public --source=. --remote=github
git push -u github main
```

بدون `gh` هم می‌شود: ریپوی خالی را در گیت‌هاب بسازید، بعد

```bash
git remote add github git@github.com:<username>/omarchy-jalali-calendar.git
git push -u github main
```

برای SSH باید کلید این ماشین در گیت‌هاب ثبت شده باشد:

```bash
ssh-keygen -t ed25519 -C "hitking@gmail.com"      # اگر کلید ندارید
cat ~/.ssh/id_ed25519.pub                          # در Settings → SSH keys بچسبانید
ssh -T git@github.com                              # باید نامتان را بگوید
```

### پوش همزمان به هر دو

اگر می‌خواهید یک `git push` هر دو جا را به‌روز کند:

```bash
git remote set-url --add --push origin https://gitea.qalam.group/masoud/omarchy-jalali-calendar.git
git remote set-url --add --push origin git@github.com:<username>/omarchy-jalali-calendar.git
```

از این به بعد `git push` هر دو مقصد را می‌زند، ولی `git pull` همچنان فقط از
Gitea می‌خوانَد. اگر یکی از دو مقصد رد کند، پوش ناتمام می‌ماند — این را در
خروجی ببینید و دوباره بزنید، نه اینکه فرض کنید هر دو رفته‌اند.

## ۵. چرخهٔ توسعه

```bash
node --test tests/*.test.js
cd sync && PYTHONPATH=. python3 -m unittest discover -s ../tests -t ..
```

بدون هیچ وابستگی. تمام حساب تاریخ در `Model.js` است که زیر node هم بار می‌شود،
دقیقاً برای همین که بشود تستش کرد. سمت پایتون هم فقط کتابخانهٔ استاندارد است.

هنگام کار روی کد، افزونهٔ نصب‌شده در
`~/.config/omarchy/plugins/masoud.jalali-calendar/` یک کلون گیت است، جدا از
پوشهٔ کاری شما. شل تغییرات همان پوشه را زیر نظر دارد و خودکار ری‌لود می‌کند، پس
برای دیدن تغییر باید به آن پوشه برسانیدش:

```bash
git -C ~/.config/omarchy/plugins/masoud.jalali-calendar pull --ff-only ~/Projects/omarchy-jalali-calendar main
```

یا بعد از اینکه پوش کردید:

```bash
omarchy plugin update masoud.jalali-calendar
```

دو نکته که وقت می‌گیرند اگر ندانید:

- **سیم‌لینک داخل پوشهٔ افزونه ممنوع است.** اعتبارسنج اُمارچی هر سیم‌لینکی را رد
  می‌کند، پس نمی‌شود پوشهٔ کاری را به پوشهٔ افزونه‌ها لینک کرد. کلون واقعی لازم است.
- **ری‌لود خودکار همیشه پنل باز را بازنمی‌سازد.** اگر تغییری در `Panel.qml` را
  نمی‌بینید، `omarchy restart shell` بزنید پیش از آنکه دنبال باگی بگردید که وجود
  ندارد. یک بار همین، نیم ساعت وقت گرفت.

بررسی خطاها:

```bash
journalctl --user -f | grep -i jalali
qmlformat Panel.qml > /dev/null          # فقط بررسی نحوی
omarchy-plugin-validate .                # اعتبارسنجی manifest
```

پنل را هم می‌شود از خط فرمان باز کرد، که برای اسکرین‌شات گرفتن به کار می‌آید:

```bash
omarchy shell jalali-calendar open
omarchy shell jalali-calendar close
```
