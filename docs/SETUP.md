# Запуск и ежедневный цикл

Как собрать, запустить и проверить приложение руками.

## Первый запуск

**Шрифты.** Martian Grotesk — SIL OFL 1.1 ([evilmartians/grotesk](https://github.com/evilmartians/grotesk)):
встраивать и распространять можно, текст лицензии лежит рядом, `<notes>/Fonts/OFL.txt`, — не удалять.
В приложении только нужные начертания: xWdUlt (логотип), xWdxBd (заголовки), StdRg и StdMd (текст).

**Перед первой сборкой** — собрать sherpa-onnx (распознавание GigaAM). Бинарники ~100 МБ в git не лежат,
скрипт качает их с релиза k2-fsa/sherpa-onnx и проверяет контрольные суммы:

```bash
./Scripts/fetch-sherpa-onnx.sh
```

```bash
open "<notes>.xcodeproj"
```

В Xcode выбери схему `<notes>`, назначение **My Mac** и нажми ⌘R. Из терминала:

```bash
xcodebuild -project "<notes>.xcodeproj" -scheme "<notes>" -destination 'platform=macOS' build
```

## Ежедневный цикл

Собрать и запустить (сборка в `build/`, он в `.gitignore`):

```bash
xcodebuild -project "<notes>.xcodeproj" -scheme "<notes>" -destination 'platform=macOS' -derivedDataPath build build
```

```bash
open "build/Build/Products/Debug/<notes>.app"
```

- В приложении есть меню «Отладка» → «Повторить загрузку» (⌘R): сцена загрузки проигрывается заново.
- Проверка вида — снимком окна и сравнением с кадром Figma бок о бок (`screencapture -l <id окна>`,
  id берётся из `CGWindowListCopyWindowInfo`). Для этого у Claude должно быть разрешение
  «Запись экрана» в настройках macOS.
- Тестовое хранилище держи **вне** репозитория: в нём будут свои git-коммиты.
- Проверить надиктовку без микрофона: положи WAV (16 кГц, 16 бит, моно) в контейнер приложения
  (`~/Library/Containers/makarkabanov/Data/tmp/`) и запусти с
  `--args -dictationTestFile <путь>` — запись пройдёт весь путь до буфера обмена.
- Окно не открылось, хотя приложение запущено — macOS «восстановила» ноль окон: запускай `open -F`.
- Главный экран на тестовой папке (настоящие заметки не трогаем): `--args -testVault YES`, сразу заметка —
  `-notesOpen "проекты/план приложения.md"`, сразу поиск — `-notesSearch синхронизация`.
- Самопроверка главного экрана — запуск бинарника из терминала, печатает ok / FAIL по каждому действию:
  `"build/Build/Products/Debug/<notes>.app/Contents/MacOS/<notes>" -testVault YES -notesSelfTest YES -ApplePersistenceIgnoreState YES`.
  Без последнего флага macOS «восстанавливает» ноль окон, и проверка не стартует.
- Сразу в раздел: `-notesSection tasks|calendar|video|settings`, страница настроек — `-settingsPage вход`.
  С `-testVault` календарь не синхронизируется — настоящий Календарь не трогаем.
- Тёмная тема без переключения системы: `--args -appearance dark`.
- Сфера надиктовки без микрофона: `--args -orbPreview listening` (или `recognizing`, `copied`).
  Тестовый WAV в `tmp` контейнера macOS со временем чистит, а терминал с подписью командой туда не пишет.
- Окно пинкода в нужном состоянии: `--args -onboardingStep 9 -pinPreview "1234 1"` (набранные цифры,
  пробел пропускается; 8 одинаковых по четыре — сохранит пинкод, потом `security delete-generic-password -s notes.pin`).
- Запуск сразу с шага онбординга: `open "build/Build/Products/Debug/<notes>.app" --args -onboardingStep 4` (10 — финал,
  11 — вход по пинкоду; с `-pinPreview 0000` — сразу набранные цифры); ⌘] — следующий шаг.
