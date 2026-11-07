library ieee;
use ieee.std_logic_1164.all;

entity uart_rx_sync is
  port (clk, rst, rx_i : in std_logic;
        rx_o, settled : out std_logic);
end entity;

architecture rtl of uart_rx_sync is
  signal rx_meta, rx_sync : std_logic := '1';
  signal fill : std_logic_vector(1 downto 0) := "00";
  attribute altera_attribute : string;
  attribute altera_attribute of rx_meta, rx_sync : signal is
    "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        rx_meta <= '1';
        rx_sync <= '1';
        fill <= "00";
      else
        rx_meta <= rx_i;
        rx_sync <= rx_meta;
        fill <= fill(0) & '1';
      end if;
    end if;
  end process;
  rx_o <= rx_sync;
  settled <= fill(1);
end architecture;
