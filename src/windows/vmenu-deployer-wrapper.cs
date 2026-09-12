// vmenu 托盘入口代理（WeaselDeployer.exe 的替身）
//
// 背景：小狼毫托盘右键菜单是 WeaselServer.exe 里的一个菜单资源，每一项对应一个固定的
// 命令号，服务端收到命令号后只会做一件事：启动安装目录下的 WeaselDeployer.exe 并带上
// 参数（见 rime/weasel 的 WeaselServerApp::SetupMenuHandlers）：
//     ID_WEASELTRAY_SETTINGS        -> WeaselDeployer.exe            （无参数）
//     ID_WEASELTRAY_DEPLOY          -> WeaselDeployer.exe /deploy    （重新部署）
//     ID_WEASELTRAY_DICT_MANAGEMENT -> WeaselDeployer.exe /dict      （用户词典管理）
//     ID_WEASELTRAY_SYNC            -> WeaselDeployer.exe /sync      （用户资料同步）
//
// 所以本项目把真正的部署器改名成 WeaselDeployer.real.exe，用本程序顶替
// WeaselDeployer.exe：
//     * 不带参数（= 托盘菜单里的「输入法设置」）→ 打开 vmenu 可视化设置窗口
//     * 带参数（/deploy /dict /sync）→ 原样转发给 WeaselDeployer.real.exe
//
// 这样既不改动「重新部署 / 用户词典管理 / 用户资料同步」，又让托盘菜单里出现
// 「输入法设置」这一项。撤销请运行 vmenu-tray-setup.ps1 -Revert。
//
// 编译（安装脚本会自动做）：
//   csc.exe /nologo /target:winexe /r:System.Windows.Forms.dll /out:WeaselDeployer.exe vmenu-deployer-wrapper.cs
// 注意：本文件必须保存为 UTF-8 带 BOM，否则 csc 会按 GBK 读源码，中文提示变乱码。

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

internal static class VMenuDeployerProxy
{
    // vmenu 可视化设置界面（WinForms 脚本），也就是输入法里按 v → 1 打开的那个窗口
    private const string GuiScript = @"D:\VibeCoding\输入法\vmenu-settings-gui.ps1";
    private const string RealDeployer = "WeaselDeployer.real.exe";
    private const string SelfName = "WeaselDeployer.exe";

    [STAThread]
    private static int Main(string[] args)
    {
        string dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        if (string.IsNullOrEmpty(dir)) dir = ".";

        if (args == null || args.Length == 0)
        {
            // 托盘「输入法设置」：打开 vmenu 设置窗口
            // （窗口脚本自己有单实例互斥体：已经开着就写标记文件让常驻实例亮出来）
            if (File.Exists(GuiScript))
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo(
                        "powershell.exe",
                        "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" +
                        GuiScript + "\" -ShowNow");
                    psi.UseShellExecute = false;
                    psi.CreateNoWindow = true;
                    psi.WindowStyle = ProcessWindowStyle.Hidden;
                    Process.Start(psi);
                    return 0;
                }
                catch (Exception ex)
                {
                    MessageBox.Show(
                        "无法打开 vmenu 设置窗口：\r\n" + GuiScript + "\r\n\r\n" + ex.Message,
                        "vmenu",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning);
                }
            }

            // 找不到 vmenu 脚本就退回原生设置对话框，避免「点了没反应」
            return RunReal(dir, "");
        }

        // 其他菜单项：原样转发给真正的部署器
        return RunReal(dir, JoinArgs(args));
    }

    private static int RunReal(string dir, string arguments)
    {
        string real = Path.Combine(dir, RealDeployer);
        if (!File.Exists(real)) real = Path.Combine(dir, SelfName); // 兜底（未安装代理时）
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo(real, arguments);
            psi.UseShellExecute = true;
            psi.WorkingDirectory = dir;
            Process.Start(psi);
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "无法启动小狼毫部署器：\r\n" + real + "\r\n\r\n" + ex.Message,
                "vmenu",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string JoinArgs(string[] args)
    {
        string s = "";
        for (int i = 0; i < args.Length; i++)
        {
            if (i > 0) s += " ";
            if (args[i].IndexOf(' ') >= 0) s += "\"" + args[i] + "\"";
            else s += args[i];
        }
        return s;
    }
}
