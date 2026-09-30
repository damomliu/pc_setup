@{
    Device = 'X870 EAGLE WIFI7'
    # 三個 ARGB 接頭預設是 0 顆，不先設定就不會變色。256 是這張板每個接頭的上限。
    ArgbLedCount = 256
    Order = @('off', 'on', 'dim', 'idle', 'cycle', 'wave')
    Modes = @{
        off = @{
            Summary = '關燈'
            Mode = 'Static'
            Color = '000000'
            Brightness = 0
        }
        on = @{
            Summary = '日常。靜態暖白'
            Mode = 'Static'
            Color = 'F2EDE4'
            Brightness = 40
        }
        dim = @{
            Summary = '低亮度琥珀，晚上或只要指示燈'
            Mode = 'Static'
            Color = 'E8873A'
            Brightness = 10
        }
        idle = @{
            Summary = '青色呼吸。機器開著，但人不在這台螢幕前'
            Mode = 'Breathing'
            Color = '3EC6FF'
            Brightness = 30
        }
        cycle = @{
            Summary = '循環。整段燈一起換色'
            Mode = 'Color Cycle'
            Brightness = 100
            Speed = 56
        }
        wave = @{
            Summary = '彩虹波浪'
            Mode = 'Wave 1'
            Brightness = 100
        }
    }
}
