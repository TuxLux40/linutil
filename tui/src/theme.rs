use clap::ValueEnum;
use ratatui::style::{Color, Style, Stylize};

// Add the Theme name here for a new theme
// This is more secure than the previous list
// We cannot index out of bounds, and we are giving
// names to our various themes, making it very clear
// This will make it easy to add new themes
#[derive(Clone, Debug, PartialEq, Default, ValueEnum, Copy)]
pub enum Theme {
    #[default]
    Default,
    Compatible,
    Neon,
}

impl Theme {
    pub const fn dir_color(&self) -> Color {
        match self {
            Theme::Default => Color::Blue,
            Theme::Compatible => Color::Blue,
            Theme::Neon => Color::Rgb(0, 255, 255),  // Cyan neon
        }
    }

    pub const fn cmd_color(&self) -> Color {
        match self {
            Theme::Default => Color::Rgb(204, 224, 208),
            Theme::Compatible => Color::LightGreen,
            Theme::Neon => Color::Rgb(0, 255, 136),  // Neon green
        }
    }

    pub const fn multi_select_disabled_color(&self) -> Color {
        match self {
            Theme::Default => Color::DarkGray,
            Theme::Compatible => Color::DarkGray,
            Theme::Neon => Color::Rgb(50, 50, 80),  // Dark purple
        }
    }

    pub const fn tab_color(&self) -> Color {
        match self {
            Theme::Default => Color::Rgb(255, 255, 85),
            Theme::Compatible => Color::Yellow,
            Theme::Neon => Color::Rgb(255, 0, 255),  // Magenta neon
        }
    }

    pub const fn dir_icon(&self) -> &'static str {
        match self {
            Theme::Default => "  ",
            Theme::Compatible => "[DIR]",
            Theme::Neon => "  ",
        }
    }

    pub const fn cmd_icon(&self) -> &'static str {
        match self {
            Theme::Default => "  ",
            Theme::Compatible => "[CMD]",
            Theme::Neon => "  ",
        }
    }

    pub const fn tab_icon(&self) -> &'static str {
        match self {
            Theme::Default => "  ",
            Theme::Compatible => ">> ",
            Theme::Neon => "  ",
        }
    }

    pub const fn multi_select_icon(&self) -> &'static str {
        match self {
            Theme::Default => "",
            Theme::Compatible => "*",
            Theme::Neon => "",
        }
    }

    pub const fn success_color(&self) -> Color {
        match self {
            Theme::Default => Color::Rgb(5, 255, 55),
            Theme::Compatible => Color::Green,
            Theme::Neon => Color::Rgb(0, 255, 136),  // Bright neon green
        }
    }

    pub const fn fail_color(&self) -> Color {
        match self {
            Theme::Default => Color::Rgb(199, 55, 44),
            Theme::Compatible => Color::Red,
            Theme::Neon => Color::Rgb(255, 0, 100),  // Neon hot pink
        }
    }

    pub const fn focused_color(&self) -> Color {
        match self {
            Theme::Default => Color::LightBlue,
            Theme::Compatible => Color::LightBlue,
            Theme::Neon => Color::Rgb(0, 255, 200),  // Bright cyan
        }
    }

    pub const fn search_preview_color(&self) -> Color {
        match self {
            Theme::Default => Color::DarkGray,
            Theme::Compatible => Color::DarkGray,
            Theme::Neon => Color::Rgb(80, 20, 100),  // Dark purple
        }
    }

    pub const fn unfocused_color(&self) -> Color {
        match self {
            Theme::Default => Color::Gray,
            Theme::Compatible => Color::Gray,
            Theme::Neon => Color::Rgb(100, 100, 150),  // Muted purple-blue
        }
    }

    #[allow(dead_code)]
    pub fn border_color(&self) -> Color {
        match self {
            Theme::Default => Color::White,
            Theme::Compatible => Color::White,
            Theme::Neon => Color::Rgb(0, 255, 255),  // Bright cyan neon glow
        }
    }

    pub fn border_style(&self) -> Style {
        match self {
            Theme::Default => Style::new(),
            Theme::Compatible => Style::new(),
            Theme::Neon => Style::new().fg(Color::Rgb(0, 255, 255)).bold(),
        }
    }

    pub fn background_color(&self) -> Color {
        match self {
            Theme::Default => Color::Reset,
            Theme::Compatible => Color::Reset,
            Theme::Neon => Color::Rgb(10, 10, 20),  // Dark space background
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
