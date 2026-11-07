library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.uart_rx_pkg.all;

entity uart_rx_tick is
  generic (CLK_HZ : positive := 75000000;
           BAUD_RATE : positive := 115200;
           OVERSAMPLE : positive := 16);
  port (clk, rst : in std_logic; sample_tick : out std_logic);
end entity;

architecture rtl of uart_rx_tick is
  constant TICK_HZ : positive := BAUD_RATE * OVERSAMPLE;
  -- Elaboration-only reduction preserves every enable, not just its average.
  constant SCALE : positive := gcd(CLK_HZ, TICK_HZ);
  constant MODULUS : positive := CLK_HZ / SCALE;
  constant STEP : positive := TICK_HZ / SCALE;
  constant THRESHOLD : integer := MODULUS - STEP;
  constant WIDTH : positive := clog2(MODULUS);
  signal phase : unsigned(WIDTH-1 downto 0) := (others => '0');
  signal wrap : std_logic;
begin
  assert OVERSAMPLE = 16 report "OVERSAMPLE must be 16" severity failure;
  assert CLK_HZ > TICK_HZ report "CLK_HZ must exceed 16 * BAUD_RATE" severity failure;
  -- Select a constant operand before one adder, rather than add/compare/subtract
  -- in series. WIDTH-bit modular arithmetic also represents the negative step.
  wrap <= '1' when phase >= THRESHOLD else '0';
  sample_tick <= wrap and not rst;
  process(clk)
    variable increment : unsigned(WIDTH-1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then phase <= (others => '0');
      else
        if wrap = '1' then increment := to_unsigned((2**WIDTH-THRESHOLD) mod 2**WIDTH, WIDTH);
        else increment := to_unsigned(STEP, WIDTH);
        end if;
        phase <= phase + increment;
      end if;
    end if;
  end process;
end architecture;
