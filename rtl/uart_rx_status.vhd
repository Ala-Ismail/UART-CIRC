library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.uart_rx_pkg.all;

entity uart_rx_status is
  generic (ERROR_COUNT_WIDTH : positive := 16);
  port (clk, rst, clear_status : in std_logic;
        framing_event, overflow_event, break_event : in std_logic;
        framing_error, overflow : out std_logic;
        framing_error_count, overflow_count, break_count : out unsigned(ERROR_COUNT_WIDTH-1 downto 0));
end entity;

architecture rtl of uart_rx_status is
  signal framing_count_reg, overflow_count_reg, break_count_reg :
    unsigned(ERROR_COUNT_WIDTH-1 downto 0) := (others => '0');
begin
  framing_error_count <= framing_count_reg;
  overflow_count <= overflow_count_reg;
  break_count <= break_count_reg;
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        framing_error <= '0'; overflow <= '0';
        framing_count_reg <= (others => '0');
        overflow_count_reg <= (others => '0');
        break_count_reg <= (others => '0');
      elsif clear_status = '1' then
        -- Event wins without routing clear through the incrementer inputs.
        framing_error <= framing_event;
        overflow <= overflow_event;
        framing_count_reg <= (others => '0');
        framing_count_reg(0) <= framing_event;
        overflow_count_reg <= (others => '0');
        overflow_count_reg(0) <= overflow_event;
        break_count_reg <= (others => '0');
        break_count_reg(0) <= break_event;
      else
        if framing_event = '1' then
          framing_count_reg <= sat_inc(framing_count_reg);
          framing_error <= '1';
        end if;
        if overflow_event = '1' then
          overflow_count_reg <= sat_inc(overflow_count_reg);
          overflow <= '1';
        end if;
        if break_event = '1' then break_count_reg <= sat_inc(break_count_reg); end if;
      end if;
    end if;
  end process;
end architecture;
