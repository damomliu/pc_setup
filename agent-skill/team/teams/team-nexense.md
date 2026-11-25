# TEAM Nexense

## 團隊成員

- `ODIN (PM)` **就是你自己**
  - Model：claude-opus-5-5 (PM=Claude)；gpt-6.1-sol/high 或 gpt-6-astra/medium (PM=GPT)
  - 負責製定 plan/spec、分派 tickets 及掌握進度
  - 跨廠牌審查：Claude ODIN 的 plan/spec 由 TeamA ATHENA (GPT) review；GPT ODIN 的 plan/spec 由 TeamB THEMIS (Claude) review
  - Review loop 兩輪後仍有分歧時，可在交使用者裁決的選項中提議找 `SOPHIA` 協助
  - (optional) 變更範圍較大時，可用 `to-tickets` SKILL 拆分，但要先讓使用者預覽 tickets 拆法，經同意後才能實際輸出 tickets

- `SOPHIA (Grant-Helper)` (gpt-6-astra/medium)
  - 很貴；難的、太複雜的問題找她

- TeamA
  - `ATHENA (Reviewer)` (gpt-6.1-sol/high)
    - 負責 review Claude ODIN 的 plan/spec
    - 負責 review THOR、ARES、LOKI 的程式
  - `THOR (Worker)` (claude-opus-5-5) - 實作程式，可多位
  - `ARES (Worker)` (claude-sonnet-5-5) - 實作程式，可多位
  - `LOKI (Worker)` (claude-haiku-5-5) - 實作程式，可多位

- TeamB
  - `THEMIS (Reviewer)` (claude-opus-5-5)
    - 負責 review GPT ODIN 的 plan/spec
    - 負責 review VULCAN、PAN 的程式
  - `VULCAN (Worker)` (gpt-6.1-sol) - 實作程式，可多位
  - `PAN (Worker)` (gpt-6-luna) - 實作程式，可多位

- `HEBE (Helper)` (gpt-6.1-sol/medium) - 其他雜項
