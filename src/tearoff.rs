use std::process::Command;

// The hand-off ui/TabBar.qml gives the one window a tear-off starts; nothing else Flea starts may inherit it.
pub const ENV: [&str; 3] = ["FLEA_TAB_SOURCE_PID", "FLEA_TAB_CURSOR", "FLEA_TAB_TOKEN"];

// A terminal or an opened program that kept these would replay a finished lift into its own Flea.
pub fn drop_env(command: &mut Command) {
    for name in ENV {
        command.env_remove(name);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_hand_off_names_the_three_variables_the_tab_bar_sets() {
        assert_eq!(ENV, ["FLEA_TAB_SOURCE_PID", "FLEA_TAB_CURSOR", "FLEA_TAB_TOKEN"]);
    }

    #[test]
    fn a_child_never_sees_a_variable_the_caller_set_for_it() {
        let mut child = Command::new("sh");
        child.args(["-c", "printf '%s' \"${FLEA_TAB_SOURCE_PID-}${FLEA_TAB_CURSOR-}${FLEA_TAB_TOKEN-}\""]);
        for name in ENV {
            child.env(name, "stale");
        }
        drop_env(&mut child);
        let out = child.output().unwrap();
        assert!(out.status.success());
        assert_eq!(String::from_utf8_lossy(&out.stdout), "");
    }

    #[test]
    fn an_unrelated_variable_survives() {
        let mut child = Command::new("sh");
        child.args(["-c", "printf '%s' \"$FLEA_TAB_UNRELATED\""]).env("FLEA_TAB_UNRELATED", "kept");
        drop_env(&mut child);
        assert_eq!(String::from_utf8_lossy(&child.output().unwrap().stdout), "kept");
    }
}
