# Layout

```
/opt/steam/steamapps/common         << steam library
    DontStarveTogether/             << game folder
        bin/                        << server
        Servers/                    << config folder
            kfs1/                   << cluster folder
                cluster_token.txt
                cluster.ini
                Overworld/
                    server.ini
                Caves/
                    server.ini
```

# Launcher

```bash
cd $GAME_FOLDER/bin

./dontstarve_dedicated_server_nullrenderer \
    -cluster "kfs1" \
    -persistent_storage_root "/opt/steam/steamapps/common/DontStarveTogether" \
    -config_dir "Servers" \
    -monitor_parent_process $$ \
    -shard "Caves" | \
        sed 's:^:[kfs1.Caves]:' &

./dontstarve_dedicated_server_nullrenderer \
    -cluster "kfs1" \
    -persistent_storage_root "/opt/steam/steamapps/common/DontStarveTogether" \
    -config_dir "Servers" \
    -monitor_parent_process $$ \
    -shard "Overworld" | \
        sed 's:^:[kfs1.Overworld]:' &

wait
```

# Replicating the setup

```powershell
./configure.ps1 -noupdate -verbose -library /opt/steam/steamapps/common -gamefolder DontStarveTogether -steamcmd steamcmd -maxplayers 4 -clusterdescription "test game" -pass "burp" -cluster "kfs1"
```

