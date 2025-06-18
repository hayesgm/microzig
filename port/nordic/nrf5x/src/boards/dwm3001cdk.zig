const microzig = @import("microzig");
pub const chip   = @import("chip");
const nrf        = microzig.hal;
const gpio       = nrf.gpio;

// ───── Board-wide conventions ──────────────────────────────────────────────
pub const led_active_state    = 0; // LEDs light when pin = 0 (active-low)
pub const button_active_state = 0; // Button pressed reads 0 (pull-up)

// ───── LEDs (D9-D12 on the schematic) ─────────────────────────────────────
pub const led0 = gpio.num(0, 4);   // D9   (GREEN)
pub const led1 = gpio.num(0, 5);   // D10  (BLUE)
pub const led2 = gpio.num(0, 22);  // D11  (RED)
pub const led3 = gpio.num(0, 14);  // D12  (RED)

pub const leds = [_]gpio.Pin{ led0, led1, led2, led3 };

// ───── Button ─────────────────────────────────────────────────────────────
pub const button_reset   = gpio.num(0, 18); // SW1 (nRESET) – usually don’t touch
pub const button_user    = gpio.num(0, 2);  // SW2 (BT_WAKE_UP)

pub const buttons = [_]gpio.Pin{};

// ───── DW3000 / “Arduino header” pins ─────────────────────────────────────
pub const dw3000_clk  = gpio.num(0,  3); // ARDUINO_13
pub const dw3000_miso = gpio.num(0, 29); // ARDUINO_12
pub const dw3000_mosi = gpio.num(0,  8); // ARDUINO_11
pub const dw3000_cs   = gpio.num(1,  6); // ARDUINO_10

pub const dw3000_wup  = gpio.num(1, 19); // ARDUINO_9
pub const dw3000_irq  = gpio.num(1,  2); // ARDUINO_8
pub const dw3000_rst  = gpio.num(0, 25); // ARDUINO_7

// ───── UART for console / debug ───────────────────────────────────────────
pub const uart_tx = gpio.num(0,19); // TX_PIN_NUMBER
pub const uart_rx = gpio.num(0,15); // RX_PIN_NUMBER

// ───── Init helper ────────────────────────────────────────────────────────
pub fn init() void {
    // Turn LEDs off (inactive state = 1)
    for (leds) |*led| {
        led.set_direction(.out);
        led.put(!led_active_state);
    }

    // Configure button with pull-up
    for (buttons) |*btn| {
        btn.set_direction(.in);
        btn.set_pull(.up);
    }
}