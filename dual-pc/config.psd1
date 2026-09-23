@{
    Version = 1

    InstallRoot = 'C:\Program Files\DualPcProfiles'
    TaskPrefix = 'DualPcProfiles'
    NetworkPrefix = '192.168.16.'

    PC = @{
        ComputerName = 'PC-DAMON-2609'
        UserName = 'user'
        IP = '192.168.16.85'
    }

    NB = @{
        ComputerName = 'NB-DAMON-2205'
        UserName = 'damon.liu'
        IP = '192.168.16.54'
    }

    SSH = @{
        Port = 22
        KeyFileName = 'dual_pc_profiles_ed25519'
        ConnectTimeoutSeconds = 5
        CommandTimeoutSeconds = 60
        RetryCount = 1
    }

    Timeouts = @{
        RequestSeconds = 120
        SpacedeskSeconds = 15
        StaleLockSeconds = 300
    }

    Spacedesk = @{
        DriverServiceName = 'spacedeskService'
        Port = 28252
        ViewerAppNamePattern = '^spacedesk(?: Windows)? VIEWER$'
        ViewerProcessNames = @(
            'spacedeskWindowsVIEWER'
            'spacedeskAppUWP'
        )
        MonitorPatterns = @(
            'spacedesk'
            'datronicsoft'
        )
    }

    PowerToys = @{
        ProcessName = 'PowerToys'
        MouseWithoutBordersProcessName = 'PowerToys.MouseWithoutBorders'
        GeneralSettingsPath = 'Microsoft\PowerToys\settings.json'
        SettingsExecutable = 'WinUI3Apps\PowerToys.Settings.exe'
        DscModule = 'DSCModules\Microsoft.PowerToys.Configure.psm1'
    }
}
