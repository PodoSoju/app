#!/usr/bin/env python3
"""
Idempotent Xcode Project Sync Script

Principles:
1. Filesystem is the source of truth - no hardcoded file lists
2. Complete regeneration - sections are fully replaced
3. Fully idempotent - N runs produce identical results
4. Auto-detection - no script changes when files change
"""

import hashlib
import subprocess
import sys
from pathlib import Path
from collections import defaultdict

PROJECT_ROOT = Path(__file__).parent.parent
PROJECT_FILE = PROJECT_ROOT / "Soju.xcodeproj" / "project.pbxproj"
SOJU_DIR = PROJECT_ROOT / "Soju"

# Fixed UUIDs matching original project - NEVER CHANGE THESE
FIXED = {
    "root_group": "A1000000EA000001",
    "soju_group": "A1000000FA000001",
    "products_group": "A10000010A000001",
    "soju_app": "A10000009A000001",
    "sojukit_ref": "A1000000CA000001",
    "sojukit_build": "A10000007A000001",
    "sojukit_dep": "A10000008A000001",
    "target": "A10000011A000001",
    "target_config_list": "A10000012A000001",
    "sources_phase": "A10000013A000001",
    "frameworks_phase": "A1000000DA000001",
    "resources_phase": "A10000014A000001",
    "project": "A10000015A000001",
    "project_config_list": "A10000016A000001",
    "debug_project": "A10000017A000001",
    "release_project": "A10000018A000001",
    "debug_target": "A10000019A000001",
    "release_target": "A1000001AA000001",
}


def uuid_for(prefix: str, path: str) -> str:
    """Generate deterministic 24-char UUID from prefix:path"""
    return hashlib.md5(f"{prefix}:{path}".encode()).hexdigest()[:24].upper()


def scan_swift_files() -> list[dict]:
    """Scan Soju/ directory for Swift files"""
    files = []
    for f in sorted(SOJU_DIR.rglob("*.swift")):
        rel = f.relative_to(PROJECT_ROOT)
        # Group path: Soju/Views/Settings/X.swift -> Views/Settings
        parts = rel.parts[1:-1]  # Skip "Soju" and filename
        group = "/".join(parts) if parts else ""

        files.append({
            "name": f.name,
            "path": str(rel),
            "group": group,
            "file_id": uuid_for("file", str(rel)),
            "build_id": uuid_for("build", str(rel)),
        })
    return files


def build_group_tree(files: list[dict]) -> dict:
    """Build group hierarchy from files"""
    tree = defaultdict(lambda: {"files": [], "subgroups": set()})

    for f in files:
        g = f["group"]
        tree[g]["files"].append(f)

        # Register parent-child relationships
        parts = g.split("/") if g else []
        for i in range(len(parts)):
            parent = "/".join(parts[:i]) if i else ""
            child = "/".join(parts[:i+1])
            tree[parent]["subgroups"].add(child)

    return dict(tree)


def generate_pbxproj(files: list[dict]) -> str:
    """Generate complete project.pbxproj content"""
    tree = build_group_tree(files)

    # === PBXBuildFile ===
    build_lines = []
    for f in sorted(files, key=lambda x: x["name"]):
        build_lines.append(
            f'\t\t{f["build_id"]} /* {f["name"]} in Sources */ = '
            f'{{isa = PBXBuildFile; fileRef = {f["file_id"]} /* {f["name"]} */; }};'
        )
    build_lines.append(
        f'\t\t{FIXED["sojukit_build"]} /* SojuKit in Frameworks */ = '
        f'{{isa = PBXBuildFile; productRef = {FIXED["sojukit_dep"]} /* SojuKit */; }};'
    )

    # === PBXFileReference ===
    ref_lines = []
    for f in sorted(files, key=lambda x: x["name"]):
        # Files in subdirs need name attribute
        if f["group"]:
            ref_lines.append(
                f'\t\t{f["file_id"]} /* {f["name"]} */ = {{isa = PBXFileReference; '
                f'includeInIndex = 1; lastKnownFileType = sourcecode.swift; '
                f'name = {f["name"]}; path = {f["path"]}; sourceTree = SOURCE_ROOT; }};'
            )
        else:
            ref_lines.append(
                f'\t\t{f["file_id"]} /* {f["name"]} */ = {{isa = PBXFileReference; '
                f'includeInIndex = 1; lastKnownFileType = sourcecode.swift; '
                f'path = {f["path"]}; sourceTree = SOURCE_ROOT; }};'
            )

    ref_lines.append(
        f'\t\t{FIXED["soju_app"]} /* Soju.app */ = {{isa = PBXFileReference; '
        f'explicitFileType = wrapper.application; includeInIndex = 0; '
        f'path = Soju.app; sourceTree = BUILT_PRODUCTS_DIR; }};'
    )
    ref_lines.append(
        f'\t\t{FIXED["sojukit_ref"]} /* SojuKit */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = wrapper; name = SojuKit; path = SojuKit; '
        f'sourceTree = "<group>"; }};'
    )

    # === PBXGroup ===
    group_lines = []

    # Root group
    group_lines.append(f'''\t\t{FIXED["root_group"]} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{FIXED["sojukit_ref"]} /* SojuKit */,
\t\t\t\t{FIXED["soju_group"]} /* Soju */,
\t\t\t\t{FIXED["products_group"]} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};''')

    # Products group
    group_lines.append(f'''\t\t{FIXED["products_group"]} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{FIXED["soju_app"]} /* Soju.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};''')

    # Helper to generate a group entry
    def gen_group_entry(gpath: str):
        info = tree.get(gpath, {"files": [], "subgroups": set()})

        if gpath == "":
            gid = FIXED["soju_group"]
            gname = "Soju"
            path_attr = "path = Soju;"
        else:
            gid = uuid_for("group", gpath)
            gname = gpath.split("/")[-1]
            path_attr = f"name = {gname};"

        children = []
        # Subgroups first
        for sub in sorted(info["subgroups"]):
            sub_name = sub.split("/")[-1]
            sub_id = uuid_for("group", sub)
            children.append(f'{sub_id} /* {sub_name} */')
        # Files
        for f in sorted(info["files"], key=lambda x: x["name"]):
            children.append(f'{f["file_id"]} /* {f["name"]} */')

        children_str = ",\n".join(f"\t\t\t\t{c}" for c in children)

        return f'''\t\t{gid} /* {gname} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{children_str},
\t\t\t);
\t\t\t{path_attr}
\t\t\tsourceTree = "<group>";
\t\t}};'''

    # Soju group (root files + subgroups)
    group_lines.append(gen_group_entry(""))

    # Recursive subgroups
    def add_subgroups(gpath: str):
        info = tree.get(gpath, {"files": [], "subgroups": set()})
        for sub in sorted(info["subgroups"]):
            group_lines.append(gen_group_entry(sub))
            add_subgroups(sub)

    add_subgroups("")

    # === PBXSourcesBuildPhase ===
    source_files = []
    for f in sorted(files, key=lambda x: x["name"]):
        source_files.append(f'\t\t\t\t{f["build_id"]} /* {f["name"]} in Sources */,')
    source_files_str = "\n".join(source_files)

    # === Full pbxproj ===
    return f'''// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_lines)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(ref_lines)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{FIXED["frameworks_phase"]} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{FIXED["sojukit_build"]} /* SojuKit in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{chr(10).join(group_lines)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{FIXED["target"]} /* Soju */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {FIXED["target_config_list"]} /* Build configuration list for PBXNativeTarget "Soju" */;
\t\t\tbuildPhases = (
\t\t\t\t{FIXED["sources_phase"]} /* Sources */,
\t\t\t\t{FIXED["frameworks_phase"]} /* Frameworks */,
\t\t\t\t{FIXED["resources_phase"]} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = Soju;
\t\t\tpackageProductDependencies = (
\t\t\t\t{FIXED["sojukit_dep"]} /* SojuKit */,
\t\t\t);
\t\t\tproductName = Soju;
\t\t\tproductReference = {FIXED["soju_app"]} /* Soju.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{FIXED["project"]} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{FIXED["target"]} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {FIXED["project_config_list"]} /* Build configuration list for PBXProject "Soju" */;
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {FIXED["root_group"]};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {FIXED["products_group"]} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{FIXED["target"]} /* Soju */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{FIXED["resources_phase"]} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{FIXED["sources_phase"]} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{source_files_str}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{FIXED["debug_project"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{FIXED["release_project"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{FIXED["debug_target"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Soju/Soju.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Soju/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Soju;
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities";
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.soju.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{FIXED["release_target"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Soju/Soju.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Soju/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Soju;
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities";
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.soju.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{FIXED["target_config_list"]} /* Build configuration list for PBXNativeTarget "Soju" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{FIXED["debug_target"]} /* Debug */,
\t\t\t\t{FIXED["release_target"]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{FIXED["project_config_list"]} /* Build configuration list for PBXProject "Soju" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{FIXED["debug_project"]} /* Debug */,
\t\t\t\t{FIXED["release_project"]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{FIXED["sojukit_dep"]} /* SojuKit */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tproductName = SojuKit;
\t\t}};
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {FIXED["project"]} /* Project object */;
}}
'''


def main():
    print("🔄 Xcode 프로젝트 동기화 시작...")

    # 1. Scan files
    files = scan_swift_files()
    print(f"📂 {len(files)}개 Swift 파일 발견")
    for f in files:
        print(f"   - {f['path']}")

    # 2. Generate and save
    content = generate_pbxproj(files)
    PROJECT_FILE.write_text(content, encoding="utf-8")
    print(f"\n✅ 프로젝트 파일 저장: {PROJECT_FILE}")

    # 3. Build test
    print("\n🔨 빌드 테스트...")
    result = subprocess.run(
        ["xcodebuild", "-scheme", "Soju", "-configuration", "Debug",
         "-derivedDataPath", "build", "-quiet", "build"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        print("✅ 빌드 성공!")
        return 0
    else:
        print("❌ 빌드 실패!")
        # Show only error lines
        for line in (result.stderr + result.stdout).split('\n'):
            if 'error:' in line.lower():
                print(f"   {line.strip()}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
