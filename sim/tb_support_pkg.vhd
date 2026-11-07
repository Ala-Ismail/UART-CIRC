library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tb_support_pkg is
  procedure clock_75mhz(signal clk : inout std_logic);
  function bit_value(b : boolean) return std_logic;
  procedure random_next(variable state : inout unsigned(31 downto 0));
end package;
package body tb_support_pkg is
  procedure clock_75mhz(signal clk : inout std_logic) is
    variable remainder_ps : natural := 0;
    variable delay_time : time;
  begin
    clk <= '0';
    loop
      delay_time := 6666 ps;
      remainder_ps := remainder_ps + 2;
      if remainder_ps >= 3 then
        delay_time := delay_time + 1 ps;
        remainder_ps := remainder_ps - 3;
      end if;
      wait for delay_time;
      clk <= not clk;
    end loop;
  end;
  function bit_value(b : boolean) return std_logic is
  begin
    if b then return '1'; else return '0'; end if;
  end;
  procedure random_next(variable state : inout unsigned(31 downto 0)) is
  begin
    state := state xor shift_left(state, 13);
    state := state xor shift_right(state, 17);
    state := state xor shift_left(state, 5);
  end;
end package body;
