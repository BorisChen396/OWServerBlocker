# Disclaimer

> ### IMPORTANT!
> This project is not affiliated with or endorsed by Blizzard Entertainment.

Please use the scripts and methods in this repository responsibly.

The developer is not responsible for any loss, damage, or other issues that may result from using the scripts provided here.

If you encounter any bugs while using the scripts, please open an issue.

# How to use?

Just [download](https://github.com/BorisChen396/OWServerBlocker/archive/refs/heads/master.zip) and extract this repository, then run the `OWServerBlocker.bat` script.

***Note:*** **DO NOT** select the wrong executable file. The `.exe` file of main game should be `Overwatch.exe` (`...\Overwatch\_retail_\Overwatch.exe` if you are using Battle.net), not `Overwatch Launcher.exe`.

> ### Note
> **DO NOT** close the command window while the script is running, as this will immediately terminate the script. The command window will close automatically when you close the selection window.

You can also run the `CreateShortcut.bat` script to create a shortcut.

# How does it work?

The script reads the contents of `IPList.json` and generates Windows Firewall rules based on the data. A brief explanation of how to create the `IPList.json` file will be provided later.

First, let's take a basic look at how Overwatch decides which server a player connects to.

Overwatch uses two types of servers:

1. **Main servers**

   These are the servers where the actual game runs. If you press `Ctrl` + `Shift` + `N` during a match, the network statistics will appear, including the server that is currently hosting the game.

2. **Relay servers**

   These servers help route your connection to the main game servers.

When you launch Overwatch, the game pings all available servers (both main and relay servers) and selects the one with the lowest latency as the main server.

The general idea behind server selection is to block unwanted servers using Windows Firewall. This makes Overwatch treat those servers as if they have higher latency than the preferred ones, causing the game to prioritize matching you with the desired servers instead.

> ### Noticeably High Latency
> If you block a main server but not the relay servers, you may still end up connecting to the blocked server through one of the relay servers. This can result in noticeably higher latency.

Lastly, when you open Battle.net, you will see three region options in the settings:

1. Americas
2. Europe
3. Asia

These regions are only used to display content on the Overwatch home page (such as Custom Game suggestions). They are **not related** to the servers used for actual gameplay.

# How to find out the IP addresses for each servers?

As mentioned earlier, we only need to identify the IP addresses of the servers that Overwatch pings when it launches, and save the information to the `IPList.json` file.

I use Wireshark, PowerShell, and Excel (to help edit CSV files) to identify the IP addresses that Overwatch communicates with when it launches.

Note that Overwatch uses both Google's and Blizzard's servers, so it may be easier to find out Google's server addresses first and exclude them from the list.

In `IPList.json`, the key `"gcp_scope"` is used to identify the GCP regions.

After obtaining the list of IP addresses, use a traceroute tool on each one and observe the address and latency of the last reachable hop. This information can help you estimate the geographical location of the IP address.

You can also use online services to assist with this, but keep in mind that the information they provide may not always be completely accurate, as some IP addresses may be used in regions different from where they are registered.

With the `ClassifyIPs.ps1` script (requires PowerShell 7+), you can simply provide a CSV file containing a list of IP addresses. The script will automatically run traceroute for each address and output the results along with the latency.

And just like that... you can generate `IPList.json` on your own!

# Small talk (You can skip this part if you want to)

This is a side project developed by IceDragon (me).

At the beginning, I just wanted a better experience while playing Overwatch. If you've ever played on Asian servers, you probably know that every Quick Play feels like Ranked.

- It's your fault for trying a new hero.
- It's your fault for being a newbie.
- If you don't play well enough, your teammates will insult you badly.

So... yeah. That's why I wanted to play on other servers.

And yes, I know this can easily be done with a VPN. But I still wanted to build this anyway. >.0

