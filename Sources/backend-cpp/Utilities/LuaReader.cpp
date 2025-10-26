// Copyright 2020 Charles Tytler

#include "LuaReader.h"

#include "lua.hpp"

#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

json get_installed_modules(const std::string &dcs_install_path, const std::string &module_subdir)
{
    json installed_modules_and_result;
    installed_modules_and_result["installed_modules"] = json::array();
    installed_modules_and_result["result"] = "";
    if (std::filesystem::exists(dcs_install_path + module_subdir)) {
        for (const auto &dir : std::filesystem::directory_iterator(dcs_install_path + module_subdir)) {
            const std::string module_abs_path = dir.path().string();
            const auto mods_subdir_str_loc = module_abs_path.find(module_subdir);
            // Determine the relative module path (relative to mods/aircraft/)
            const std::string rel_module_path = module_abs_path.substr(mods_subdir_str_loc + module_subdir.size(),
                                                                        module_abs_path.size());

            // Try to detect if the module contains variants in its Cockpit folder (e.g. Mirage-F1\Mirage-F1BE)
            // If so, add entries for each variant that contains a clickabledata.lua. Otherwise add the base module.
            try {
                std::filesystem::path cockpit_path = std::filesystem::path(module_abs_path) / "Cockpit";
                bool added_variant = false;
                if (std::filesystem::exists(cockpit_path) && std::filesystem::is_directory(cockpit_path)) {
                    // If clickabledata exists directly under Cockpit or under Cockpit/Scripts,
                    // prefer the base module entry (e.g., TF-51D) so the extractor searches the standard locations.
                    std::filesystem::path direct_candidate = cockpit_path / "clickabledata.lua";
                    std::filesystem::path scripts_candidate = cockpit_path / "Scripts" / "clickabledata.lua";
                    if (std::filesystem::exists(direct_candidate) || std::filesystem::exists(scripts_candidate)) {
                        installed_modules_and_result["installed_modules"].push_back(rel_module_path);
                        added_variant = true;
                    } else {
                        // Otherwise, search for variant subfolders (exclude common folder names like "Scripts").
                        for (const auto &sub : std::filesystem::directory_iterator(cockpit_path)) {
                            if (!std::filesystem::is_directory(sub.path())) continue;
                            const std::string subname = sub.path().filename().string();
                            if (subname == "Scripts") continue; // not a variant

                            // First check if clickabledata exists directly under this first-level subdir
                            std::filesystem::path candidate1 = sub.path() / "clickabledata.lua";
                            std::filesystem::path candidate2 = sub.path() / "Scripts" / "clickabledata.lua";
                            if (std::filesystem::exists(candidate1) || std::filesystem::exists(candidate2)) {
                                std::string variant_key = rel_module_path;
                                if (variant_key.size() > 0 && (variant_key.back() == '/' || variant_key.back() == '\\')) {
                                    variant_key.pop_back();
                                }
                                // Use '|' as internal delimiter between module and variant path
                                variant_key += "|" + subname;
                                installed_modules_and_result["installed_modules"].push_back(variant_key);
                                added_variant = true;
                                continue;
                            }

                            // Otherwise check one level deeper: sub/sub2
                            if (std::filesystem::exists(sub.path()) && std::filesystem::is_directory(sub.path())) {
                                for (const auto &sub2 : std::filesystem::directory_iterator(sub.path())) {
                                    if (!std::filesystem::is_directory(sub2.path())) continue;
                                    const std::string sub2name = sub2.path().filename().string();
                                    if (sub2name == "Scripts") continue;
                                    std::filesystem::path candidate21 = sub2.path() / "clickabledata.lua";
                                    std::filesystem::path candidate22 = sub2.path() / "Scripts" / "clickabledata.lua";
                                    if (std::filesystem::exists(candidate21) || std::filesystem::exists(candidate22)) {
                                        std::string variant_key = rel_module_path;
                                        if (variant_key.size() > 0 && (variant_key.back() == '/' || variant_key.back() == '\\')) {
                                            variant_key.pop_back();
                                        }
                                        // Build variant subpath using backslashes (relative to Cockpit)
                                        std::string variant_subpath = subname + "\\" + sub2name;
                                        variant_key += "|" + variant_subpath;
                                        installed_modules_and_result["installed_modules"].push_back(variant_key);
                                        added_variant = true;
                                    }
                                }
                            }
                        }
                    }
                }
                // If no clickabledata was found in Cockpit or variants, fall back to adding the base module
                if (!added_variant) {
                    installed_modules_and_result["installed_modules"].push_back(rel_module_path);
                }
            } catch (const std::exception &e) {
                // On error, include the base module as a best-effort fallback
                installed_modules_and_result["installed_modules"].push_back(
                    module_abs_path.substr(mods_subdir_str_loc + module_subdir.size(), module_abs_path.size()));
            }
        }
        installed_modules_and_result["result"] = "success";
    } else {
        installed_modules_and_result["result"] =
            "DCS Install path [" + dcs_install_path + module_subdir + "] not found.";
    }
    return installed_modules_and_result;
}

json get_clickabledata(const std::string &dcs_install_path,
                       const std::string &module_name,
                       const std::string &lua_script)
{
    json clickabledata_and_result;
    clickabledata_and_result["clickabledata_items"] = json::array();
    clickabledata_and_result["result"] = "";

    // create new Lua state
    lua_State *lua_state;
    lua_state = luaL_newstate();

    // load Lua libraries
    luaL_openlibs(lua_state);

    // Write variables to lua, the below sends to lua: [module_name = "A-10C"]
    lua_pushstring(lua_state, dcs_install_path.c_str());
    lua_setglobal(lua_state, "dcs_install_path");
    lua_pushstring(lua_state, module_name.c_str());
    lua_setglobal(lua_state, "module_name");

    // Run the lua script file, expecting multiple return values.
    const int lua_stack_size = lua_gettop(lua_state);
    const int file_status = luaL_loadfile(lua_state, lua_script.c_str());
    if (file_status != 0) {
        clickabledata_and_result["result"] =
            "Lua file load error (" + std::to_string(file_status) + "): " + lua_tostring(lua_state, -1);
        lua_close(lua_state);
        return clickabledata_and_result;
    }
    const int script_status = lua_pcall(lua_state, 0, LUA_MULTRET, 0);
    if (script_status != 0) {
        clickabledata_and_result["result"] =
            "Lua script runtime error (" + std::to_string(script_status) + "): " + lua_tostring(lua_state, -1);
        lua_close(lua_state);
        return clickabledata_and_result;
    }

    // Handle each of the return values one at a time.
    while ((lua_gettop(lua_state) - lua_stack_size) > 0) {
        clickabledata_and_result["result"] = "success";
        clickabledata_and_result["clickabledata_items"].push_back(lua_tostring(lua_state, lua_gettop(lua_state)));
        lua_pop(lua_state, 1);
    }

    // close the Lua state
    lua_close(lua_state);

    return clickabledata_and_result;
}
