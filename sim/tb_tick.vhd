library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.tb_support_pkg.all;

entity tb_tick is generic (BAUD : positive := 4000000); end entity;
architecture test of tb_tick is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal tick : std_logic;
begin
  clock_75mhz(clk);
  dut : entity work.uart_rx_tick generic map(75000000, BAUD, 16) port map(clk, rst, tick);
  process
    variable reference_phase, total_ticks, last_tick, interval : natural := 0;
    constant LOW_INTERVAL : natural := 75000000/(BAUD*16);
  begin
    wait until rising_edge(clk); wait until falling_edge(clk); rst <= '0';
    for cycle in 1 to 100000 loop
      wait until rising_edge(clk);
      reference_phase := reference_phase + BAUD*16;
      assert tick=bit_value(reference_phase>=75000000) report "Tick sequence" severity failure;
      if tick='1' then
        total_ticks:=total_ticks+1;
        interval:=cycle-last_tick;
        if last_tick>0 then
          assert interval=LOW_INTERVAL or interval=LOW_INTERVAL+1 report "Tick jitter" severity failure;
        end if;
        last_tick:=cycle;
        reference_phase:=reference_phase-75000000;
      end if;
    end loop;
    assert total_ticks=integer(100000.0*real(BAUD)*16.0/75000000.0-0.5)
      report "Tick average frequency" severity failure;
    report "PASS tb_tick baud=" & integer'image(BAUD) & " enables=" & integer'image(total_ticks);
    finish;
  end process;
  process begin wait for 2 ms; assert false report "Tick timeout" severity failure; end process;
end architecture;
