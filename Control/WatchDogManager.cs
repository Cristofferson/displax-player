/*
 * Xibo - Digitial Signage - http://www.xibo.org.uk
 * Copyright (C) 2020 Xibo Signage Ltd
 *
 * This file is part of Xibo.
 *
 * Xibo is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version. 
 *
 * Xibo is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with Xibo.  If not, see <http://www.gnu.org/licenses/>.
 */
using System;
using System.Diagnostics;
using System.IO;

namespace XiboClient.Control
{
    class WatchDogManager
    {
        public static void Start()
        {
            // Check to see if the WatchDog EXE exists where we expect it to be
            // Uncomment to test local watchdog install. 
            //string path = @"C:\Program Files (x86)\Xibo Player\watchdog\x86\XiboClientWatchdog.exe";
            string executablePath = Process.GetCurrentProcess().MainModule.FileName;
            string productName = ApplicationSettings.GetProductNameFromAssembly();
            string watchDogFolder = Path.GetDirectoryName(executablePath) + @"\watchdog";
            string path = watchDogFolder + @"\x86\" + ((productName != "Xibo") ? productName + "Watchdog.exe" : "XiboClientWatchdog.exe");
            string args = "-p \"" + executablePath + "\" -l \"" + ApplicationSettings.Default.LibraryPath + "\"";

            // A screen that only shows the content as a screen saver has no player to keep
            // alive. The watchdog cannot tell that apart: it sees no DisplaxPlayer.exe process
            // and starts one every minute, forever, because it also cannot tell a crash from a
            // window someone closed on purpose. The installer drops this marker on those
            // machines and removes it when the same machine is reinstalled as a normal player.
            //
            // This one is logged. The File.Exists below is silent when the watchdog is simply
            // missing, and that silence has already cost us a player that looked perfect and
            // never recovered from a hang - one silent skip in this method is enough.
            string disabledMarker = Path.Combine(watchDogFolder, "disabled");
            if (File.Exists(disabledMarker))
            {
                Trace.WriteLine(new LogMessage("WatchDogManager - Start", "Not starting the watchdog: disabled by " + disabledMarker), LogType.Info.ToString());
                return;
            }

            // Start it
            if (File.Exists(path))
            {
                try
                {
                    Process process = new Process();
                    ProcessStartInfo info = new ProcessStartInfo();

                    info.CreateNoWindow = true;
                    info.WindowStyle = ProcessWindowStyle.Hidden;
                    info.FileName = "cmd.exe";
                    info.Arguments = "/c start \"watchdog\" \"" + path + "\" " + args;

                    process.StartInfo = info;
                    process.Start();
                }
                catch (Exception e)
                {
                    Trace.WriteLine(new LogMessage("WatchDogManager - Start", "Unable to start: " + e.Message), LogType.Error.ToString());
                }
            }
        }
    }
}
