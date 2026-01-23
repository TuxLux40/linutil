use clap::ValueEnum;
use ratatui::style::Color;

// Add the Theme name here for a new theme
// This is more secure than the previous list
// We cannot index out of bounds, and we are giving
// names to our various themes, making it very clear
// This will make it easy to add new themes
#[derive(Clone, Debug, PartialEq, Default, ValueEnum, Copy)]
pub enum Theme {
    #[default]
    Default,
}

impl Theme {
    pub const fn dir_color(&self) -> Color {
        match self {
            Theme::Default => Color::LightCyan,
        }
    }

    pub const fn cmd_color(&self) -> Color {
        match self {
            Theme::Default => Color::White,
        }
    }

    pub const fn multi_select_disabled_color(&self) -> Color {
        match self {
            Theme::Default => Color::DarkGray,
        }
    }

    pub const fn tab_color(&self) -> Color {
        match self {
            Theme::Default => Color::Yellow,
        }
    }

    pub const fn dir_icon(&self) -> &'static str {
        match self {
            Theme::Default => "[D]",
        }
    }

    pub const fn cmd_icon(&self) -> &'static str {
        match self {
            Theme::Default => "[*]",
        }
    }

    pub const fn tab_icon(&self) -> &'static str {
        match self {
            Theme::Default => ">> ",
        }
    }

    pub const fn multi_select_icon(&self) -> &'static str {
        match self {
            Theme::Default => "*",
        }
    }

    pub const fn success_color(&self) -> Color {
        match self {
            Theme::Default => Color::LightGreen,
        }
    }

    pub const fn fail_color(&self) -> Color {
        match self {
            Theme::Default => Color::LightRed,
        }
    }

    pub const fn focused_color(&self) -> Color {
        match self {
            Theme::Default => Color::LightBlue,
        }
    }

    pub const fn search_preview_color(&self) -> Color {
        match self {
            Theme::Default => Color::DarkGray,
        }
    }

    pub const fn unfocused_color(&self) -> Color {
        match self {
            Theme::Default => Color::Gray,
        }
    }
}

impl Theme {
    pub fn next(&mut self) {
        let position = *self as usize;
        let types = Theme::value_variants();
        *self = types[(position + 1) % types.len()];
    }

    pub fn prev(&mut self) {
        let position = *self as usize;
        let types = Theme::value_variants();
        *self = types[(position + types.len() - 1) % types.len()];
    }
}
