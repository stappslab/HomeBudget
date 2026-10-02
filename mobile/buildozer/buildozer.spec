[app]
# HomeBudget Android package configuration
 title = HomeBudget
 package.name = homebudget
 package.domain = org.homebudget
 source.dir = ..
 source.include_exts = py,sqlite3,json,png,jpg,kv
 version = 0.1.0
 requirements = python3,kivy
 orientation = portrait
 fullscreen = 0
 android.api = 35
 android.minapi = 24
 android.archs = arm64-v8a, armeabi-v7a
 android.allow_backup = True
p4a.fork = kivy
p4a.branch = develop

[buildozer]
 log_level = 2
 warn_on_root = 1
