library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.uart_rx_pkg.all;

entity uart_rx_circular is
  generic (CLK_HZ : positive := 75000000;
           BAUD_RATE : positive := 115200;
           OVERSAMPLE : positive := 16;
           FIFO_DEPTH : positive := 512;
           ERROR_COUNT_WIDTH : positive := 16);
  port (clk, rst, uart_rx_i, rd_req, clear_status : in std_logic;
        rd_ready : out std_logic;
        rd_data : out std_logic_vector(7 downto 0);
        rd_valid, empty, full : out std_logic;
        level : out unsigned(clog2(FIFO_DEPTH+1)-1 downto 0);
        rx_busy, framing_error, overflow, break_active : out std_logic;
        framing_error_count, overflow_count, break_count : out unsigned(ERROR_COUNT_WIDTH-1 downto 0));
end entity;

architecture rtl of uart_rx_circular is
  signal rx_sync, settled, tick, valid_byte : std_logic;
  signal data_byte : std_logic_vector(7 downto 0);
  signal framing_event, overflow_event, break_event : std_logic;
begin
  sync_inst : entity work.uart_rx_sync port map(clk, rst, uart_rx_i, rx_sync, settled);
  tick_inst : entity work.uart_rx_tick generic map(CLK_HZ, BAUD_RATE, OVERSAMPLE)
    port map(clk, rst, tick);
  core_inst : entity work.uart_rx_core
    port map(clk, rst, tick, rx_sync, settled, data_byte, valid_byte,
             framing_event, break_event, break_active, rx_busy);
  -- Registered core byte is accepted by the FIFO on the following rising edge.
  fifo_inst : entity work.uart_rx_fifo generic map(FIFO_DEPTH)
    port map(clk, rst, data_byte, valid_byte, rd_req, rd_ready, rd_data,
             rd_valid, empty, full, overflow_event, level);
  status_inst : entity work.uart_rx_status generic map(ERROR_COUNT_WIDTH)
    port map(clk, rst, clear_status, framing_event, overflow_event, break_event,
             framing_error, overflow, framing_error_count, overflow_count, break_count);
end architecture;
