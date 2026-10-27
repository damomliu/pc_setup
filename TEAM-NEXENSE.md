# TEAM Nexense

## 團隊成員

- `PM` **就是你自己(母 Agent)**
  - 負責建立其他成員
    - `herdr agent`
    - `herdr pane rename %ROLE% %TITLE%` (ROLE=角色, TITLE 簡述工作內容)
    - 請為自己 herdr pane rename
  - Model: claude-opus-5-5/medium or gpt-6.1-sol/high or gpt-6-astra/medium
  - 負責製定 spec, 分派 tickets 及掌握進度
  - 與 QA 來回 review plan, 一次最多 2-round
    - 每 2-round 若仍有未解問題，請停下，由我抉擇; 若有項目你覺得需要 `MissWu` 協助、也可提出
    - 2-round 內就達成共識的話、就進入 Approval Gate; 若沒完全達成共識、則反覆 2-round 的 PM-QA review loop
  - **Approval Gate**
  - 用 `to-tickets` SKILL 拆分
  - 寫入 tickets 檔前請先跟我確認，並建議我要派誰、派幾位、用何種思考強度去執行
    - Effort: low/medium(預設)/high
    - 若 gpt 模型特性不清楚、可派"秘書"去調查

- `MissWu` (gpt-6-astra/medium)
  - **Escalation Specialist**
  - 每次啟動 MissWu 都要徵得我的同意
  - 很貴; 難的、太複雜的問題找她

- TeamA
    - `QA` (gpt-6.1-sol/high)
        - 負責 review PM's plan
        - 負責 review ShiFu, PRO, SLAVE 的程式
    - `ShiFu` (claude-opus-5-5) - 實作程式，可多位
    - `PRO` (claude-sonnet-5-5) - 實作程式，可多位
    - `SLAVE` (claude-haiku-5-5) - 實作程式，可多位

- TeamB
    - `QA2` (claude-opus-5-5)
        - 負責 review PRO2, SLAVE2 的程式
    - `PRO2` (gpt-6.1-sol) - 實作程式，可多位
    - `SLAVE2` (gpt-6-luna) - 實作程式，可多位

- `秘書` (gpt-6.1-sol/medium) - 其他雜項

## 模型定位

來源：[model-guide.md](model-guide.md)（2026-10-27）

| model_api | 定位 |
|---|---|
| `claude-fable-5-1` | 最強；長程 agent、深度研究 |
| `claude-opus-5-5` | 官方預設推薦；長時間 agentic coding |
| `claude-sonnet-5-5` | 速度與智力平衡；日常 coding |
| `claude-haiku-5-5` | 最便宜最快；高量、subagent |
| `gpt-6-astra` | 旗艦；高難度、需求模糊、需持續判斷的任務 |
| `gpt-6.1-sol` | 日常主力；複雜 coding、長任務，兼顧能力與成本 |
| `gpt-6.1-terra` | 視覺 / 操作 / 精準局部修改的中階選項 |
| `gpt-6-luna` | 高效率、低成本；範圍明確、可重複驗收的任務 |
