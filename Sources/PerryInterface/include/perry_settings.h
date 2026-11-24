#ifndef PERRY_SETTINGS_H
#define PERRY_SETTINGS_H

// The PERRY_* environment variables, from perry_settings.def: an id for
// each, and a table of their names, kinds, groups and summaries.

#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>

typedef enum perry_setting_kind {
    perry_setting_flag,
    perry_setting_bool01,
    perry_setting_number,
    perry_setting_string,
    perry_setting_path,
    perry_setting_list,
    perry_setting_dynamic,
} perry_setting_kind;

typedef enum perry_setting_id {
#define PERRY_SETTING(name, kind, group, help, summary) PERRY_SETTING_##name,
#include "perry_settings.def"
#undef PERRY_SETTING
    PERRY_SETTING_COUNT
} perry_setting_id;

typedef struct perry_setting {
    const char *name;
    perry_setting_kind kind;
    const char *group;
    bool help;
    const char *summary;
} perry_setting;

#define perry_setting_help true
#define perry_setting_detail false

static const perry_setting perry_settings[PERRY_SETTING_COUNT] = {
#define PERRY_SETTING(name, kind, group, help, summary) \
    {"PERRY_" #name, perry_setting_##kind, group, perry_setting_##help, summary},
#include "perry_settings.def"
#undef PERRY_SETTING
};

/// The setting's value, or NULL when unset.
static inline const char *perry_setting_value(perry_setting_id id) {
    return getenv(perry_settings[id].name);
}

/// Whether a flag is set, or a bool01 setting is set and not "0".
static inline bool perry_setting_on(perry_setting_id id) {
    const char *value = perry_setting_value(id);
    if (!value) return false;
    return perry_settings[id].kind == perry_setting_flag || (value[0] && !(value[0] == '0' && value[1] == 0));
}

#endif
