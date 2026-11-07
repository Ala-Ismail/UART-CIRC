library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.uart_rx_pkg.all;
use work.tb_support_pkg.all;

entity tb_fifo is
  generic (DEPTH : positive := 512; SEED : positive := 17);
end entity;
architecture test of tb_fifo is
  signal clk : std_logic := '0';
  signal rst, valid_i, req : std_logic := '0';
  signal data_i, data_o : std_logic_vector(7 downto 0) := (others => '0');
  signal ready, valid_o, empty, full, drop_event : std_logic;
  signal level : unsigned(clog2(DEPTH+1)-1 downto 0);
begin
  clock_75mhz(clk);
  dut : entity work.uart_rx_fifo generic map(DEPTH)
    port map(clk, rst, data_i, valid_i, req, ready, data_o, valid_o,
             empty, full, drop_event, level);
  process
    type queue_t is array(0 to DEPTH-1) of std_logic_vector(7 downto 0);
    variable queue : queue_t;
    variable head, tail, count, reads, writes, wraps : natural := 0;
    type coverage_t is array(0 to 2, 0 to 3) of natural;
    variable coverage : coverage_t := (others => (others => 0));
    variable rng : unsigned(31 downto 0) := to_unsigned(SEED, 32);
    procedure step(w, r : boolean; value : natural := 0; reset : boolean := false) is
      variable accept_read, accept_write, dropped : boolean;
      variable expected : std_logic_vector(7 downto 0);
      variable occupancy_bin, operation_bin : natural;
    begin
      wait until falling_edge(clk);
      rst <= bit_value(reset); valid_i <= bit_value(w); req <= bit_value(r);
      data_i <= std_logic_vector(to_unsigned(value mod 256, 8));
      wait for 1 ps;
      assert ready = bit_value(count > 0 and not reset) severity failure;
      accept_read := r and count > 0 and not reset;
      accept_write := w and count < DEPTH and not reset;
      dropped := w and count = DEPTH and not reset;
      assert drop_event = bit_value(dropped) report "FIFO drop decision" severity failure;
      if count = 0 then occupancy_bin := 0;
      elsif count = DEPTH then occupancy_bin := 2;
      else occupancy_bin := 1; end if;
      operation_bin := boolean'pos(w)*2 + boolean'pos(r);
      if not reset then coverage(occupancy_bin, operation_bin) := coverage(occupancy_bin, operation_bin)+1; end if;
      if reset then head := 0; tail := 0; count := 0;
      else
        if accept_read then
          expected := queue(head); head := (head+1) mod DEPTH;
          count := count-1; reads := reads+1;
        end if;
        if accept_write then
          queue(tail) := std_logic_vector(to_unsigned(value mod 256, 8));
          tail := (tail+1) mod DEPTH;
          if tail = 0 then wraps := wraps+1; end if;
          count := count+1; writes := writes+1;
        end if;
      end if;
      wait until rising_edge(clk); wait for 1 ps;
      assert valid_o = bit_value(accept_read) report "FIFO read validity" severity failure;
      if accept_read then assert data_o = expected report "FIFO data order" severity failure; end if;
      assert to_integer(level) = count report "FIFO occupancy" severity failure;
      assert empty = bit_value(count = 0) and full = bit_value(count = DEPTH)
        report "FIFO flags" severity failure;
    end procedure;
  begin
    step(false, false, reset => true);
    for boundary in 0 to 2 loop
      for op in 0 to 3 loop
        step(false, false, reset => true);
        if boundary > 0 then
          step(true, false, 165);
          if boundary = 2 then
            for i in 2 to DEPTH loop step(true, false, i); end loop;
          end if;
        end if;
        step(op >= 2, op mod 2 = 1, 90);
      end loop;
    end loop;
    step(false, false, reset => true);
    for lap in 1 to 21 loop
      for i in 0 to DEPTH-1 loop step(true, false, i+lap); end loop;
      for i in 1 to 8 loop step(true, false, 33); end loop;
      step(true, true, 44); -- full plus pop still drops
      for i in 1 to DEPTH-1 loop step(false, true); end loop;
      step(false, true);
    end loop;
    for i in 1 to 30000 loop
      random_next(rng);
      step(rng(0)='1', rng(1)='1', to_integer(rng(15 downto 8)), i mod 997 = 0);
    end loop;
    for i in 1 to DEPTH+1 loop step(false, true); end loop;
    step(true, true, 123, true);
    step(false, true);
    assert wraps >= 20 report "FIFO wrap coverage" severity failure;
    for boundary in 0 to 2 loop
      for op in 0 to 3 loop
        assert coverage(boundary, op)>0 report "FIFO boundary coverage hole" severity failure;
      end loop;
    end loop;
    report "COVER FIFO all 12 boundary/operation bins; wraps=" & integer'image(wraps);
    report "PASS tb_fifo depth=" & integer'image(DEPTH) & " seed=" & integer'image(SEED);
    finish;
  end process;
  process begin wait for 10 ms; assert false report "FIFO timeout" severity failure; end process;
end architecture;
