library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.uart_rx_pkg.all;

entity uart_rx_fifo is
  generic (FIFO_DEPTH : positive := 512);
  port (clk, rst : in std_logic;
        byte_data : in std_logic_vector(7 downto 0);
        byte_valid, rd_req : in std_logic;
        rd_ready : out std_logic;
        rd_data : out std_logic_vector(7 downto 0);
        rd_valid, empty, full, overflow_event : out std_logic;
        level : out unsigned(clog2(FIFO_DEPTH+1)-1 downto 0));
end entity;

architecture rtl of uart_rx_fifo is
  constant PTR_BITS : positive := clog2(FIFO_DEPTH);
  type ram_t is array(0 to FIFO_DEPTH-1) of std_logic_vector(7 downto 0);
  signal ram : ram_t;
  signal wr_ptr, rd_ptr : unsigned(PTR_BITS-1 downto 0) := (others => '0');
  signal count : unsigned(clog2(FIFO_DEPTH+1)-1 downto 0) := (others => '0');
  signal push, pop : std_logic;
  signal empty_i, full_i, ready_i : std_logic;
begin
  assert FIFO_DEPTH >= 2 and is_power_of_two(FIFO_DEPTH)
    report "FIFO_DEPTH must be a power of two >= 2" severity failure;
  empty_i <= '1' when count = 0 else '0';
  -- For power-of-two depth and legal occupancy, the top bit alone means full.
  full_i <= count(count'high);
  empty <= empty_i;
  full <= full_i;
  rd_ready <= ready_i;
  level <= count;
  ready_i <= not empty_i and not rst;
  push <= byte_valid and not full_i and not rst;
  pop <= rd_req and ready_i;
  overflow_event <= byte_valid and full_i and not rst;

  -- No reset on RAM or its read-data register, preserving synchronous RAM inference.
  process(clk)
  begin
    if rising_edge(clk) then
      if push = '1' then ram(to_integer(wr_ptr)) <= byte_data; end if;
      if pop = '1' then rd_data <= ram(to_integer(rd_ptr)); end if;
    end if;
  end process;
  process(clk)
    variable increment : unsigned(count'range);
  begin
    if rising_edge(clk) then
      rd_valid <= '0';
      if rst = '1' then
        wr_ptr <= (others => '0');
        rd_ptr <= (others => '0');
        count <= (others => '0');
      else
        rd_valid <= pop;
        if push = '1' then wr_ptr <= wr_ptr + 1; end if;
        if pop = '1' then rd_ptr <= rd_ptr + 1; end if;
        if push /= pop then
          -- One carry chain for +/-1: 00...001 on push, 11...111 on pop.
          increment := (others => pop);
          increment(0) := '1';
          count <= count + increment;
        end if;
      end if;
    end if;
  end process;
  -- synthesis translate_off
  process(clk)
    variable expected_wr, expected_rd : natural := 0;
    variable expected_count : natural := 0;
  begin
    if rising_edge(clk) then
      assert to_integer(wr_ptr)=expected_wr and to_integer(rd_ptr)=expected_rd
        report "FIFO pointer movement/wrap" severity failure;
      assert count=expected_count report "FIFO count update" severity failure;
      if rst='1' then
        expected_wr:=0; expected_rd:=0; expected_count:=0;
      else
        assert not (push = '1' and pop = '1' and wr_ptr = rd_ptr)
          report "FIFO read/write address collision" severity failure;
        if push='1' then
          expected_wr:=(expected_wr+1) mod FIFO_DEPTH;
          expected_count:=expected_count+1;
        end if;
        if pop='1' then
          expected_rd:=(expected_rd+1) mod FIFO_DEPTH;
          expected_count:=expected_count-1;
        end if;
      end if;
    end if;
  end process;
  -- synthesis translate_on
end architecture;
