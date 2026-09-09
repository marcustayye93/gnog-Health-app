#!/usr/bin/env python3
"""Generate ios/Gnog.xcodeproj/project.pbxproj for the Gnog Schedules app.

One app target "Gnog" + one WidgetKit extension target "GnogWidgets".
Deterministic IDs (md5 of a stable name) so regenerating is idempotent.
"""
import hashlib
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "Gnog.xcodeproj", "project.pbxproj")

APP_SOURCES = [
    "Gnog/GnogApp.swift",
    "Gnog/Models.swift",
    "Gnog/PackLogic.swift",
    "Gnog/PredictionEngine.swift",
    "Gnog/HealthKitManager.swift",
    "Gnog/NotificationManager.swift",
    "Gnog/SnapshotWriter.swift",
    "Gnog/FlowMood.swift",
    "Gnog/Shared/AppGroup.swift",
    "Gnog/Views/TodayView.swift",
    "Gnog/Views/CalendarView.swift",
    "Gnog/Views/PackView.swift",
    "Gnog/Views/InsightsView.swift",
    "Gnog/Views/SettingsView.swift",
]
WIDGET_SOURCES = [
    "GnogWidgets/GnogWidgets.swift",
    "Gnog/Shared/AppGroup.swift",
]
OTHER_FILES = [
    "Gnog/Info.plist",
    "Gnog/Gnog.entitlements",
    "GnogWidgets/Info.plist",
    "GnogWidgets/GnogWidgets.entitlements",
]
ASSET_CATALOG = "Gnog/Assets.xcassets"


def nid(name: str) -> str:
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def q(s: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_.$/]+", s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def arr(items, indent):
    if not items:
        return "()"
    pad = "\t" * indent
    inner = "".join(f"{pad}\t{i},\n" for i in items)
    return f"(\n{inner}{pad})"


objects = []  # (id, comment, dict_of_fields_in_order)


def add(id_, comment, fields):
    objects.append((id_, comment, fields))


# ---------------------------------------------------------------- file refs
fileref = {}
for f in APP_SOURCES + WIDGET_SOURCES + OTHER_FILES + [ASSET_CATALOG]:
    if f in fileref:
        continue
    fid = nid("fileref:" + f)
    name = os.path.basename(f)
    if f.endswith(".swift"):
        ftype = "sourcecode.swift"
    elif f.endswith(".xcassets"):
        ftype = "folder.assetcatalog"
    elif f.endswith(".plist"):
        ftype = "text.plist.xml"
    elif f.endswith(".entitlements"):
        ftype = "text.plist.entitlements"
    else:
        ftype = "text"
    fileref[f] = fid
    add(fid, name, {
        "isa": "PBXFileReference",
        "lastKnownFileType": ftype,
        "path": f,
        "sourceTree": '"<group>"',
    })

# products
app_product = nid("product:Gnog.app")
add(app_product, "Gnog.app", {
    "isa": "PBXFileReference",
    "explicitFileType": "wrapper.application",
    "includeInIndex": "0",
    "path": "Gnog.app",
    "sourceTree": "BUILT_PRODUCTS_DIR",
})
ext_product = nid("product:GnogWidgets.appex")
add(ext_product, "GnogWidgets.appex", {
    "isa": "PBXFileReference",
    "explicitFileType": "wrapper.app-extension",
    "includeInIndex": "0",
    "path": "GnogWidgets.appex",
    "sourceTree": "BUILT_PRODUCTS_DIR",
})

# ---------------------------------------------------------------- build files
def buildfile(fileref_id, comment, target):
    bid = nid(f"buildfile:{target}:{comment}")
    add(bid, f"{comment} in Sources", {
        "isa": "PBXBuildFile",
        "fileRef": f"{fileref_id} /* {comment} */",
    })
    return bid


app_source_files = [buildfile(fileref[f], os.path.basename(f), "app") for f in APP_SOURCES]
widget_source_files = [buildfile(fileref[f], os.path.basename(f), "widget") for f in WIDGET_SOURCES]

# asset catalog goes in the app Resources phase
assets_bf = nid("buildfile:app:assets")
add(assets_bf, "Assets.xcassets in Resources", {
    "isa": "PBXBuildFile",
    "fileRef": f"{fileref[ASSET_CATALOG]} /* Assets.xcassets */",
})

# embed appex build file
embed_bf = nid("buildfile:embed:appex")
add(embed_bf, "GnogWidgets.appex in Embed App Extensions", {
    "isa": "PBXBuildFile",
    "fileRef": f"{ext_product} /* GnogWidgets.appex */",
    "settings": {"ATTRIBUTES": "(RemoveHeadersOnCopy, )"},
})

# ---------------------------------------------------------------- phases
def phase(kind, name, files, extra=None):
    pid = nid(f"phase:{kind}:{name}")
    fields = {"isa": kind, "buildActionMask": "2147483647", "files": files,
              "runOnlyForDeploymentPostprocessing": "0"}
    if kind == "PBXCopyFilesBuildPhase":
        fields["dstPath"] = '""'
        fields["dstSubfolderSpec"] = "13"
        fields["name"] = q(name)
    if extra:
        fields.update(extra)
    add(pid, name, fields)
    return pid


app_sources_ph = phase("PBXSourcesBuildPhase", "Sources", app_source_files)
app_fw_ph = phase("PBXFrameworksBuildPhase", "Frameworks", [])
app_res_ph = phase("PBXResourcesBuildPhase", "Resources", [assets_bf])
app_embed_ph = phase("PBXCopyFilesBuildPhase", "Embed App Extensions", [embed_bf])
widget_sources_ph = phase("PBXSourcesBuildPhase", "Sources", widget_source_files)
widget_fw_ph = phase("PBXFrameworksBuildPhase", "Frameworks", [])
widget_res_ph = phase("PBXResourcesBuildPhase", "Resources", [])

# ---------------------------------------------------------------- groups
def group(name, children, path=None):
    gid = nid("group:" + name)
    fields = {"isa": "PBXGroup", "children": children, "sourceTree": '"<group>"'}
    if path:
        fields["path"] = q(path)
    else:
        fields["name"] = q(name)
    add(gid, name, fields)
    return gid


views_group = group("Views", [fileref[f] for f in APP_SOURCES if "/Views/" in f], path="Views")
shared_group = group("Shared", [fileref["Gnog/Shared/AppGroup.swift"]], path="Shared")
nog_group = group("Gnog", [
    fileref["Gnog/GnogApp.swift"],
    fileref["Gnog/Models.swift"],
    fileref["Gnog/PackLogic.swift"],
    fileref["Gnog/PredictionEngine.swift"],
    fileref["Gnog/HealthKitManager.swift"],
    fileref["Gnog/NotificationManager.swift"],
    fileref["Gnog/SnapshotWriter.swift"],
    fileref["Gnog/FlowMood.swift"],
    views_group,
    shared_group,
    fileref["Gnog/Info.plist"],
    fileref["Gnog/Gnog.entitlements"],
    fileref[ASSET_CATALOG],
], path="Gnog")
widgets_group = group("GnogWidgets", [
    fileref["GnogWidgets/GnogWidgets.swift"],
    fileref["GnogWidgets/Info.plist"],
    fileref["GnogWidgets/GnogWidgets.entitlements"],
], path="GnogWidgets")
products_group = group("Products", [app_product, ext_product])
main_group = group("Gnog", [nog_group, widgets_group, products_group])

# ---------------------------------------------------------------- configs
def xcconfig(name, settings):
    cid = nid("xcconfig:" + name)
    add(cid, name, {
        "isa": "XCBuildConfiguration",
        "buildSettings": settings,
        "name": q(name),
    })
    return cid


def xclist(name, configs):
    lid = nid("xclist:" + name)
    add(lid, name, {
        "isa": "XCConfigurationList",
        "buildConfigurations": configs,
        "defaultConfigurationIsVisible": "0",
        "defaultConfigurationName": "Release",
    })
    return lid


proj_debug = xcconfig("proj:Debug", {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
})
proj_release = xcconfig("proj:Release", {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "SWIFT_COMPILATION_MODE": "wholemodule",
})
proj_list = xclist("project", [proj_debug, proj_release])


def target_settings(bundle_id, plist, entitlements, extra=None):
    s = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CODE_SIGN_ENTITLEMENTS": q(entitlements),
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": q(plist),
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks")',
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": q(bundle_id),
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SDKROOT": "iphoneos",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1",
    }
    if extra:
        s.update(extra)
    return s


app_debug = xcconfig("app:Debug", target_settings(
    "com.gnog.schedules", "Gnog/Info.plist", "Gnog/Gnog.entitlements",
    {"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES",
     "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"'}))
app_release = xcconfig("app:Release", target_settings(
    "com.gnog.schedules", "Gnog/Info.plist", "Gnog/Gnog.entitlements",
    {"DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
     "SWIFT_OPTIMIZATION_LEVEL": '"-Owholemodule"'}))
app_list = xclist("app", [app_debug, app_release])

widget_debug = xcconfig("widget:Debug", target_settings(
    "com.gnog.schedules.GnogWidgets", "GnogWidgets/Info.plist", "GnogWidgets/GnogWidgets.entitlements",
    {"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "SKIP_INSTALL": "YES",
     "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"'}))
widget_release = xcconfig("widget:Release", target_settings(
    "com.gnog.schedules.GnogWidgets", "GnogWidgets/Info.plist", "GnogWidgets/GnogWidgets.entitlements",
    {"DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"', "SKIP_INSTALL": "YES",
     "SWIFT_OPTIMIZATION_LEVEL": '"-Owholemodule"'}))
widget_list = xclist("widget", [widget_debug, widget_release])

# ---------------------------------------------------------------- targets
project_id = nid("project")
app_target = nid("target:app")
widget_target = nid("target:widget")

# container proxy + dependency (app -> widget)
proxy_id = nid("proxy:widget")
add(proxy_id, "PBXContainerItemProxy", {
    "isa": "PBXContainerItemProxy",
    "containerPortal": f"{project_id} /* Project object */",
    "proxyType": "1",
    "remoteGlobalIDString": widget_target,
    "remoteInfo": "GnogWidgets",
})
dep_id = nid("dep:app->widget")
add(dep_id, "PBXTargetDependency", {
    "isa": "PBXTargetDependency",
    "target": f"{widget_target} /* GnogWidgets */",
    "targetProxy": f"{proxy_id} /* PBXContainerItemProxy */",
})

add(app_target, "Gnog", {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": f"{app_list} /* Build configuration list for PBXNativeTarget \"Gnog\" */",
    "buildPhases": [app_sources_ph, app_fw_ph, app_res_ph, app_embed_ph],
    "buildRules": "()",
    "dependencies": [dep_id],
    "name": "Gnog",
    "productName": "Gnog",
    "productReference": f"{app_product} /* Gnog.app */",
    "productType": '"com.apple.product-type.application"',
})
add(widget_target, "GnogWidgets", {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": f"{widget_list} /* Build configuration list for PBXNativeTarget \"GnogWidgets\" */",
    "buildPhases": [widget_sources_ph, widget_fw_ph, widget_res_ph],
    "buildRules": "()",
    "dependencies": "()",
    "name": "GnogWidgets",
    "productName": "GnogWidgets",
    "productReference": f"{ext_product} /* GnogWidgets.appex */",
    "productType": '"com.apple.product-type.app-extension"',
})

add(project_id, "Project object", {
    "isa": "PBXProject",
    "attributes": {
        "BuildIndependentTargetsInParallel": "1",
        "LastSwiftUpdateCheck": "1500",
        "LastUpgradeCheck": "1500",
        "TargetAttributes": {
            app_target: {"CreatedOnToolsVersion": "15.0"},
            widget_target: {"CreatedOnToolsVersion": "15.0"},
        },
    },
    "buildConfigurationList": f"{proj_list} /* Build configuration list for PBXProject \"Gnog\" */",
    "compatibilityVersion": '"Xcode 15.0"',
    "developmentRegion": "en",
    "hasScannedForEncodings": "0",
    "knownRegions": ["en", "Base"],
    "mainGroup": f"{main_group}",
    "productRefGroup": f"{products_group} /* Products */",
    "projectDirPath": '""',
    "projectRoot": '""',
    "targets": [app_target, widget_target],
})

# ---------------------------------------------------------------- serialize
def ser(v, indent):
    if isinstance(v, dict):
        if not v:
            return "{}"
        pad = "\t" * indent
        inner = "".join(f"{pad}\t{k} = {ser(x, indent + 1)};\n" for k, x in v.items())
        return "{\n" + inner + pad + "}"
    if isinstance(v, list):
        return arr(v, indent)
    return str(v)


lines = [
    "// !$*UTF8*$!",
    "{",
    "\tarchiveVersion = 1;",
    "\tclasses = {",
    "\t};",
    "\tobjectVersion = 56;",
    "\tobjects = {",
]

for id_, comment, fields in objects:
    lines.append(f"\t\t{id_} /* {comment} */ = {{")
    for k, v in fields.items():
        lines.append(f"\t\t\t{k} = {ser(v, 3)};")
    lines.append("\t\t};")

lines += [
    "\t};",
    f"\trootObject = {project_id} /* Project object */;",
    "}",
]


os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    f.write("\n".join(lines) + "\n")
print("wrote", OUT, f"({len(objects)} objects)")
