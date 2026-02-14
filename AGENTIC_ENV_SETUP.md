# AGENTIC_ENV_SETUP.md

## Призначення

Цей файл фіксує фактичний стан налаштувань агентного середовища для `frankenssh` станом на **2026-02-14**:

- orchestration через `ntm`
- координація через MCP Agent Mail
- індексація/памʼять через `cass` + `cm`
- skills через `ms`
- guardrail-інструменти (`ubs`, Agent Mail git guard, `dcg`)
- очищення Agent Mail від зайвих агентів через офіційний CLI (`projects prune-agents`)

Документ описує не тільки “що увімкнено”, а й тонкощі, які прибирають тертя в щоденній роботі.

---

## 1. Архітектура оточення

Робоча схема:

1. `ntm` створює tmux-сесію агентів у `/data/projects/frankenssh`.
2. Під час spawn `ntm` авто-реєструє кожен pane як окремого Agent Mail агента (випадкове валідне імʼя виду `AdjectiveNoun`).
3. Після spawn hook повідомляє кожному pane його **фактичне** Agent Mail імʼя.
4. Агенти працюють із MCP Agent Mail через endpoint `http://127.0.0.1:8765/api/`.
5. Mail UI доступний за `http://127.0.0.1:8765/mail/` (проєкт `data-projects-frankenssh`).
6. `cass` дає історичний пошук; `cm` дає контекст поверх індексу `cass`.
7. `ms` працює як skill-indexer і як MCP server (`ms mcp serve`).

---

## 2. Глобальні налаштування (поза репо)

### `~/.config/ntm/config.toml`

Ключові параметри:

- `projects_base = "/data/projects"`
- `[agent_mail]`
  - `enabled = true`
  - `url = "http://127.0.0.1:8765/api/"`
  - `auto_register = true`
  - `program_name = "ntm"`
- `[agents].codex` перевизначено без застарілого флага `--enable web_search=live` (він ламав старт Codex pane у поточній версії CLI).
- `[gemini_setup]`
  - `auto_select_pro_model = false` (щоб `ntm spawn` не блокувався на auto-setup Gemini model picker і не зависав на timeout)
- `[recovery]`
  - `enabled = false`
  - `auto_inject_on_spawn = false`
  - офіційно вимикає smart session recovery інжект у freshly spawned pane-агенти
- `[context_rotation]`
  - `enabled = false`
  - прибирає автоматичні context-rotation інтервенції з додатковими recovery prompt-ами

### `~/.config/ntm/hooks.toml`

`post-spawn` hook `agent-mail-pane-bootstrap`:

1. Читає реєстр `ntm` для поточної сесії:  
   `~/.config/ntm/sessions/<session>/<project-slug>/agent_registry.json`
2. Мапить `pane_id -> pane_index` через `tmux list-panes`.
3. Надсилає в кожен pane коротке повідомлення з уже призначеним Agent Mail імʼям.

Реалізаційна деталь:
- hook використовує прямий `tmux send-keys` (а не `ntm send`), щоб уникнути рекурсивного виклику `ntm` всередині `post-spawn` і потенційних зависань.

Це важливо, бо:

- уникаємо дубль-реєстрацій `register_agent` вручну
- не губимо відповідність pane ↔ agent_name
- `agent_name` для MCP викликів одразу відомий агенту

### `~/.zshrc.local`

Є місток для Agent Mail env:

- `AGENT_MAIL_URL` -> `http://127.0.0.1:8765/api/`
- `AGENT_MAIL_TOKEN` -> з `MCP_AM_TOKEN` (якщо задано)
- ініціалізація `ntm shell zsh` тільки в interactive shell
- для детермінованого spawn без автопідхоплення старих задач:
  - `NTM_RECOVERY_ENABLED=false`
  - `NTM_RECOVERY_AUTO_INJECT=false`

### MCP у CLI-агентах

- Claude: `mcp-agent-mail` + `meta-skill` підключені й в статусі connected.
- Codex: `mcp-agent-mail` + `meta-skill` підключені.
- Gemini: endpoint Agent Mail вказано на `/api/`.

---

## 3. Локальні налаштування в репо `frankenssh`

### `.ubsignore`

Додано для зменшення шуму UBS:

- `target/`
- `legacy_openssh_code/`
- `artifacts/`
- `.beads/*.db*`
- `Cargo.lock`

### `.gitignore`

Додано ignore для runtime-стану `ntm`, щоб не засмічувати `git status`:

- `.ntm/pids/`
- `.ntm/logs/`
- `.ntm/summaries/`
- `.ntm/human_inbox/`
- `.ntm/rate_limits.json`

Додано конвенцію для персональних локальних файлів агентів/розробників:

- `.local/`
- `.agent-work/`

Рекомендація: будь-які тимчасові нотатки, чернетки, export-и, проміжні діагностичні файли складати тільки в один із цих каталогів.

### Agent Mail guard hooks (git)

Встановлено pre-commit + pre-push guard для перевірок file reservations Agent Mail в цьому репо.

---

## 4. Ініціалізація даних інструментів

### `cass`

- Виконано `cass index --full`.
- Поточний стан: `cass status` -> Healthy, база заповнена.

### `cm`

- Виконано `cm init`.
- Створено:
  - `~/.cass-memory/config.json`
  - `~/.cass-memory/playbook.yaml`
  - `~/.cass-memory/blocked.log`
  - `~/.cass-memory/usage.jsonl`

Після індексації `cass` команда `cm context "SSH wire parsing" --json` працює без degraded-режиму.

### `ms`

- MCP server: `ms mcp serve`
- Skill paths проіндексовано (`ms index --all`)
- `ms doctor` проходить
- `ms` встановлено з офіційного `upstream/main`:
  `cargo install --git https://github.com/Dicklesworthstone/meta_skill --branch main ms --force`
  (commit `e624dcf`, включає `fix(mcp): protocol compliance for Codex and concurrent access`)
- це усуває помилку Codex startup:
  `MCP client for meta-skill failed to start ... initialize response`

---

## 5. Правильний старт робочої сесії

> Важливо: для `ntm spawn` **не існує** прапорця `--spawn-dir` у поточній версії.

Рекомендований старт:

```bash
cd /data/projects/frankenssh
ntm spawn frankenssh --cc=1 --cod=1 --gmi=1
```

Після spawn очікувана поведінка:

1. `ntm` реєструє pane-агентів у Agent Mail автоматично.
2. Hook надсилає в кожен pane його `agent_name`.
3. Кожен агент викликає MCP `fetch_inbox` уже зі своїм реальним іменем.

---

## 6. Перевірка стану (smoke-check)

```bash
acfs doctor
ntm doctor
claude mcp list
codex mcp list
cass status
cm context "SSH wire parsing" --json
ms doctor
ntm status frankenssh
curl -s http://127.0.0.1:8765/mail/api/projects/data-projects-frankenssh/agents
```

Очікувано:

- `acfs doctor`: зелений, окрім опційного `network.ssh_keepalive` warning
- `ntm doctor`: HEALTHY, можливі optional warnings по не-critical tools
- MCP Agent Mail та Meta Skill: connected
- `cass` healthy
- `cm context`: структурована відповідь, не degraded
- `ntm status frankenssh`: або здорова активна сесія, або `session not found` якщо сесія ще не піднята
- Mail API `/mail/api/projects/data-projects-frankenssh/agents`: повертає актуальний список агентів

### 6.1 Поточний стан агентів у Mail

Станом на 2026-02-14 у `data-projects-frankenssh` — **0 агентів** (повний prune).

Усі агенти (coordinator `NavyHollow`, pane-агенти claude-code/codex-cli/gemini-cli) реєструються автоматично при `ntm spawn` з випадковими іменами і живуть тільки поки сесія активна. Після `ntm kill` + `prune-agents` всі видаляються.

Будь-які накопичені тимчасові/дубльовані агенти прибираються через `projects prune-agents`.

### 6.2 Безпечне очищення зайвих агентів (без костилів)

Використовувати тільки офіційну CLI-команду `projects prune-agents` у `mcp_agent_mail`; не чіпати SQLite вручну.

Dry-run:

```bash
cd /home/ubuntu/mcp_agent_mail
.venv/bin/python -m mcp_agent_mail.cli projects prune-agents data-projects-frankenssh \
  --keep-latest-per-program 0
```

Apply:

```bash
cd /home/ubuntu/mcp_agent_mail
.venv/bin/python -m mcp_agent_mail.cli projects prune-agents data-projects-frankenssh \
  --keep-latest-per-program 0 \
  --apply --yes
```

---

## 7. Тонкощі та пастки

1. `ntm spawn ... --spawn-dir=...`  
   Помилка: такого прапорця немає. Запускати із правильного CWD або через `projects_base`.

2. `codex` флаг `--enable web_search=live`  
   У поточному Codex CLI це ламає запуск pane (`Unknown feature flag`). Видалено з `ntm` codex command template.

3. Команда `am list-projects`  
   У цьому середовищі `am` як shell-команда відсутня. Для пошти/агентів використовувати MCP tools або `ntm mail ...`.

4. Перший spawn нового session-name  
   Може дати recovery warning по inbox до первинної реєстрації session coordinator. Після першої реєстрації зазвичай зникає.

5. Імена агентів  
   `ntm` генерує їх автоматично. Не треба примусово перереєстровувати з “ручними” іменами без окремої причини.

6. Старі плани можуть містити застарілі кроки  
   У файлі `/home/ubuntu/.claude/plans/hazy-puzzling-feather.md` є щонайменше 3 неактуальні пункти:
   - `ntm spawn ... --spawn-dir=...` (прапорця немає)
   - `am list-projects` (команда відсутня в цьому shell)
   - зауваження про `bd not found` як blocking/error (у поточному `ntm doctor` це не blocking failure)

7. Auto-recovery може неочікувано інжектити “continue bead” контекст  
   Стабільний спосіб: зафіксувати в `~/.config/ntm/config.toml`:
   - `[recovery].enabled = false`
   - `[recovery].auto_inject_on_spawn = false`
   За потреби дублювати env-перемінними:
   - `NTM_RECOVERY_ENABLED=false`
   - `NTM_RECOVERY_AUTO_INJECT=false`

8. Gemini CLI auto-update loop
   gemini-cli при запуску через bun перевіряє оновлення, але auto-updater захардкоджений на `npm`.
   Результат: оновлює через npm в інший global dir, а `$PATH` далі резолвить стару bun-версію → нескінченний loop.
   Відомі баги: [#13807](https://github.com/google-gemini/gemini-cli/issues/13807), [#15632](https://github.com/google-gemini/gemini-cli/issues/15632).
   **Фікс:** auto-update вимкнено через `~/.gemini/settings.json`:
   ```json
   { "general": { "enableAutoUpdateNotification": false } }
   ```
   Оновлення тільки через `acfs update --agents-only` (використовує `bun install -g`).

---

## 8. Поточний baseline версій (практично важливі)

- `acfs`: `0.6.0`
- `ntm`: `1.7.0`
- `cass`: `0.1.64`
- `cm`: `0.2.3`
- `ms`: `0.1.1`
- `rch`: `1.0.8`
- `dcg`: `0.4.0`
- `br` (`beads_rust`): `0.1.13`
- `gemini-cli`: `0.28.2` (auto-update вимкнено, оновлення через `acfs update`)

---

## 9. Що вважати “готовим до розробки”

Середовище вважається підготовленим, якщо одночасно виконано:

1. `acfs doctor` без fail.
2. `ntm doctor` = HEALTHY.
3. MCP Agent Mail + Meta Skill підключені для Claude/Codex.
4. `cass status` healthy та `cm context` повертає контекст.
5. `ntm spawn frankenssh ...` піднімає pane-агентів без фатальних помилок старту.
6. У Mail проєкту лишаються тільки потрібні активні агенти, зайві видаляються через `projects prune-agents`.

---

## 10. Політика актуальності документації

Оновлювати цей файл в той самий день, коли змінено:

1. глобальні конфіги (`~/.config/ntm/*`, MCP settings, hook-и);
2. локальні guardrail-файли (`.ubsignore`, `.gitignore`, Agent Mail guard);
3. склад агентів у Mail (`/mail/api/projects/<slug>/agents`);
4. baseline версій інструментів або smoke-check процедуру.

---

## 11. Остання валідація (2026-02-14)

- `cargo fmt --check` — pass
- `cargo check --all-targets` — pass
- `cargo clippy --all-targets -- -D warnings` — pass
- `cargo test --workspace` — pass (у workspace наразі немає реалізованих тест-кейсів, всі crates показали `0 tests`)
- `.venv/bin/pytest -q tests/test_cli_extended.py` у `/home/ubuntu/mcp_agent_mail` — pass (включно з тестом для `projects prune-agents`)
- `curl -s http://127.0.0.1:8765/mail/api/projects/data-projects-frankenssh/agents` → `{"agents":[]}` (агенти зʼявляються після `ntm spawn`)

### 11.1 Операційний smoke-check (2026-02-14, після підйому сесії `frankenssh`)

- `ntm list` → `frankenssh: 1 windows (attached)` + додаткова стороння сесія `repo-updater-parity`
- `ntm status frankenssh` → 4 panes (user + Claude + Codex + Gemini), Agent Mail connected
- `cass status` → Healthy, last indexed 4 minutes ago, `Conversations: 447`, `Messages: 18226`
- `cm context "wire parsing" --json` → success, структурований JSON зі snippet-ами
- `ms doctor` (CLI) може повернути `LockBusy`, якщо активний `ms mcp serve` тримає Tantivy lock; у такому випадку перевіряти health через MCP server (`meta-skill`)
- `ubs --only=rust /data/projects/frankenssh --ci` → `Critical: 0`, `Warning: 0`, `Info: 14` (warnings закрито: `unwrap`/`try_into().unwrap()` замінено на `?`-propagation)
- `br ready --json` (у CWD `/data/projects/frankenssh`) → 5 ready items, включно з `fsh-690` у `in_progress`
- `codex exec "Reply with exactly: MCP-OK"` → `mcp startup: ready: meta-skill, mcp-agent-mail`, відповідь `MCP-OK`, без `MCP startup incomplete`
