library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package uart_rx_pkg is
  function clog2(n : positive) return natural;
  function is_power_of_two(n : positive) return boolean;
  function gcd(a, b : positive) return positive;
  function sat_inc(n : unsigned) return unsigned;
end package;

package body uart_rx_pkg is
  function clog2(n : positive) return natural is
    variable value : natural := n - 1;
    variable bits : natural := 0;
  begin
    while value > 0 loop
      value := value / 2;
      bits := bits + 1;
    end loop;
    return bits;
  end;

  function is_power_of_two(n : positive) return boolean is
    variable value : positive := n;
  begin
    while value > 1 loop
      if value mod 2 /= 0 then return false; end if;
      value := value / 2;
    end loop;
    return true;
  end;

  function gcd(a, b : positive) return positive is
    variable x : natural := a;
    variable y : natural := b;
    variable remainder_value : natural;
  begin
    while y /= 0 loop
      remainder_value := x mod y;
      x := y;
      y := remainder_value;
    end loop;
    return x;
  end;

  function sat_inc(n : unsigned) return unsigned is
    variable incremented : unsigned(n'length downto 0);
  begin
    -- Use arithmetic carry-out instead of a separate full-width all-ones decode.
    incremented := resize(n, n'length+1) + 1;
    if incremented(n'length) = '1' then return n; end if;
    return incremented(n'length-1 downto 0);
  end;
end package body;
