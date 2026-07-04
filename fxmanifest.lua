fx_version "cerulean"
game "rdr3"
rdr3_warning "I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships."

name "weathersync"
author "kibukj"
description "Optimized time and weather synchronization for RedM"
version "2.0.0"

ui_page "ui/index.html"

files {
    "ui/index.html",
    "ui/*.css",
    "ui/*.js",
    "ui/CHINESER.TTF"
}

shared_scripts {
    "shared/utils.lua",
    "config.lua"
}

client_scripts {
    "client/main.lua",
    "client/interface.lua",
    "client/commands.lua",
    "client/tests.lua"
}

server_scripts {
    "server/main.lua",
    "server/commands.lua",
    "server/tests.lua"
}
