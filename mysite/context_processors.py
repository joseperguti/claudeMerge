from django.conf import settings


def ui_theme_settings(_request):
    return {
        'UI_FONT_FAMILY': getattr(settings, 'UI_FONT_FAMILY', "'Segoe UI', Tahoma, sans-serif"),
        'DISPLAY_FONT_FAMILY': getattr(settings, 'DISPLAY_FONT_FAMILY', "'Segoe UI', Tahoma, sans-serif"),
        'GOOGLE_FONTS_URL': getattr(settings, 'GOOGLE_FONTS_URL', ''),
    }
