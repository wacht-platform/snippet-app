// Public entry point for Mission Control. The screen and supporting widgets
// live in this directory; this file re-exports the entry function so existing
// callers (`lib/screens/desktop_shell.dart`) keep working.
library;

export 'mission_control/mission_control_screen.dart'
    show MissionControlScreen, openMissionControl;
export 'mission_control/mission_control_state.dart'
    show isDedicatedMcSession, isMissionControlListRow;
