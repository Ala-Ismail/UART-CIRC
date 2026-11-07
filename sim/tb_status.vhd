library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_support_pkg.all;

entity tb_status is generic (WIDTH : positive := 16); end entity;
architecture test of tb_status is
  signal clk : std_logic := '0';
  signal rst, clear, fe, oe, be : std_logic := '0';
  signal framing, overflow : std_logic;
  signal fc, oc, bc : unsigned(WIDTH-1 downto 0);
begin
  clock_75mhz(clk);
  dut : entity work.uart_rx_status generic map(WIDTH)
    port map(clk, rst, clear, fe, oe, be, framing, overflow, fc, oc, bc);
  process
    variable f, o, b : natural := 0;
    variable fs, os : boolean := false;
    constant MAXIMUM : natural := 2**WIDTH-1;
    procedure step(events : natural; clear_i : boolean := false; reset : boolean := false) is
    begin
      wait until falling_edge(clk);
      rst <= bit_value(reset); clear <= bit_value(clear_i);
      fe <= bit_value(events mod 2 = 1); oe <= bit_value((events/2) mod 2=1);
      be <= bit_value(events>=4);
      if reset or clear_i then f:=0; o:=0; b:=0; fs:=false; os:=false; end if;
      if not reset then
        if events mod 2=1 then if f<MAXIMUM then f:=f+1; end if; fs:=true; end if;
        if (events/2) mod 2=1 then if o<MAXIMUM then o:=o+1; end if; os:=true; end if;
        if events>=4 then if b<MAXIMUM then b:=b+1; end if; end if;
      end if;
      wait until rising_edge(clk); wait for 1 ps;
      assert to_integer(fc)=f and to_integer(oc)=o and to_integer(bc)=b
        report "Diagnostic counters" severity failure;
      assert framing=bit_value(fs) and overflow=bit_value(os)
        report "Diagnostic sticky flags" severity failure;
    end;
  begin
    step(0, reset=>true);
    for events in 0 to 7 loop
      step(events); step(events, true); step(0); step(events, true, true);
    end loop;
    for i in 1 to MAXIMUM+5 loop step(7); end loop;
    step(0); step(0, true); step(0);
    report "COVER STATUS all event/clear combinations; reset priority; saturation";
    report "PASS tb_status width=" & integer'image(WIDTH);
    finish;
  end process;
  process begin wait for 10 ms; assert false report "Status timeout" severity failure; end process;
end architecture;
