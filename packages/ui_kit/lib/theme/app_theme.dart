/// Role-aware theming is owned by the shared core package.
///
/// This file remains the historical entry point used by `ui_kit` consumers;
/// it now re-exports the unified [AppTheme] factory so there is exactly one
/// theme implementation in the monorepo.
library;
export 'package:core/core.dart'
    show AppRole, AppTheme, RoleThemeExtension, RoleThemeContext;
