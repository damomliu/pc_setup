# TEAM Nexense

成員的 agent / model / effort 見 [../models.json](../models.json) 的 `teams.nexense`，key 為角色名小寫。

## 團隊成員

- `ODIN (PM)` **就是你自己**
  - 模型建議見 `teams.nexense.pm`
  - 負責製定 plan/spec、分派 tickets 及掌握進度
  - 跨廠牌審查：Claude ODIN 的 plan/spec 由 TeamA ATHENA (GPT) review；GPT ODIN 的 plan/spec 由 TeamB THEMIS (Claude) review
  - Review loop 兩輪後仍有分歧時，可在交使用者裁決的選項中提議找 `SOPHIA` 協助
  - (optional) 變更範圍較大時，可用 `to-tickets` SKILL 拆分，但要先讓使用者預覽 tickets 拆法，經同意後才能實際輸出 tickets

- `SOPHIA (Grant-Helper)`
  - 很貴；難的、太複雜的問題找她

- TeamA
  - `ATHENA (Reviewer)`
    - 負責 review Claude ODIN 的 plan/spec
    - 負責 review THOR、ARES、LOKI 的程式
  - `THOR (Worker)` - 實作程式，可多位
  - `ARES (Worker)` - 實作程式，可多位
  - `LOKI (Worker)` - 實作程式，可多位

- TeamB
  - `THEMIS (Reviewer)`
    - 負責 review GPT ODIN 的 plan/spec
    - 負責 review VULCAN、PAN 的程式
  - `VULCAN (Worker)` - 實作程式，可多位
  - `PAN (Worker)` - 實作程式，可多位

- `HEBE (Helper)` - 其他雜項
