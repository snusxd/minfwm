#pragma once

#include <ApplicationServices/ApplicationServices.h>

class ClientWindow
{
public:
    explicit ClientWindow(AXUIElementRef windowRef);
    ~ClientWindow();

    // Prevent copying
    ClientWindow(const ClientWindow&) = delete;
    ClientWindow& operator=(const ClientWindow&) = delete;

    // Absolute coordinates on the infinite canvas
    double absolute_x = 0.0;
    double absolute_y = 0.0;
    double width = 0.0;
    double height = 0.0;

    bool is_hidden = false;
    bool is_floating = false;
    CGWindowID wid = 0;

    double start_screen_x = 0.0;
    double start_screen_y = 0.0;

    AXUIElementRef GetRef() const { return m_windowRef; }

private:
    AXUIElementRef m_windowRef;
};
