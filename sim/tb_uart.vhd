library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.uart_rx_pkg.all;
use work.tb_support_pkg.all;

entity tb_uart is
  generic (BAUD : positive := 4000000; SUITE : natural := 0; SEED : positive := 1;
           MATRIX_OFFSET : integer := 3);
end entity;
architecture test of tb_uart is
  constant BIT_TIME : time := 1 sec / BAUD;
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal rx : std_logic := '1';
  signal req, clear : std_logic := '0';
  signal ready, valid_o, empty, full, busy, framing, overflow, active : std_logic;
  signal data_o : std_logic_vector(7 downto 0);
  signal level : unsigned(9 downto 0);
  signal fc, oc, bc : unsigned(15 downto 0);
  signal expected_toggle : std_logic := '0';
  signal expected_data : std_logic_vector(7 downto 0) := (others=>'0');
  signal pending, received : natural := 0;
begin
  clock_75mhz(clk);
  dut : entity work.uart_rx_circular generic map(75000000, BAUD, 16, 512, 16)
    port map(clk, rst, rx, req, clear, ready, data_o, valid_o, empty, full,
             level, busy, framing, overflow, active, fc, oc, bc);
  scoreboard : process
    type queue_t is array(0 to 65535) of std_logic_vector(7 downto 0);
    variable queue : queue_t;
    variable head, tail, count, responses : natural := 0;
    variable seen : std_logic := '0';
  begin
    wait until rising_edge(clk);
    if rst='1' then
      head:=0; tail:=0; count:=0; responses:=0; seen:=expected_toggle;
    elsif expected_toggle/=seen then
      assert count<queue'length report "Test queue overflow" severity failure;
      queue(tail):=expected_data; tail:=(tail+1) mod queue'length; count:=count+1;
      seen:=expected_toggle;
    end if;
    wait for 1 ps;
    if rst='0' and valid_o='1' then
      assert count>0 report "Unexpected UART response" severity failure;
      assert data_o=queue(head)
        report "UART data mismatch got=" & to_hstring(data_o) & " expected=" & to_hstring(queue(head)) severity failure;
      head:=(head+1) mod queue'length; count:=count-1; responses:=responses+1;
    end if;
    assert to_integer(level)<=512 report "UART level out of range" severity failure;
    assert empty=bit_value(level=0) and full=bit_value(level=512)
      report "UART occupancy flags" severity failure;
    pending<=count; received<=responses;
  end process;

  stimulus : process
    variable rng : unsigned(31 downto 0) := to_unsigned(SEED,32);
    variable drops, expected_framing, expected_breaks : natural := 0;
    variable duration : time;
    variable allow_read, accept_byte : boolean;
    variable completed_frames : natural := 0;
    procedure cycles(n : positive) is
    begin for i in 1 to n loop wait until falling_edge(clk); end loop; end;
    procedure initialize is
    begin
      rst<='1'; req<='0'; rx<='1'; clear<='0'; cycles(5);
      rst<='0'; cycles(8); wait for BIT_TIME;
      drops:=0; expected_framing:=0; expected_breaks:=0;
    end;
    procedure frame(value : natural; period : time := BIT_TIME;
                    good_stop : boolean := true; expect_byte : boolean := true) is
      variable bits : std_logic_vector(7 downto 0);
    begin
      bits:=std_logic_vector(to_unsigned(value mod 256,8));
      if expect_byte then
        expected_data<=bits; expected_toggle<=not expected_toggle;
      end if;
      rx<='0'; wait for period;
      for bit_index in 0 to 7 loop rx<=bits(bit_index); wait for period; end loop;
      rx<=bit_value(good_stop); wait for period;
      completed_frames:=completed_frames+1;
    end;
    procedure drain is
    begin
      rx<='1'; req<='1'; wait for 2*BIT_TIME; cycles(530); wait for 1 ps;
      assert pending=0 and level=0 report "UART drain incomplete / missing bytes" severity failure;
      req<='0';
    end;
    procedure diagnostics is
    begin
      cycles(8); wait for 1 ps;
      assert to_integer(fc)=expected_framing report "Framing count mismatch" severity failure;
      assert to_integer(oc)=drops report "Overflow count mismatch" severity failure;
      assert to_integer(bc)=expected_breaks report "Break count mismatch" severity failure;
      assert framing=bit_value(expected_framing>0) and overflow=bit_value(drops>0)
        report "Sticky flags mismatch" severity failure;
    end;
  begin
    report "CONFIG tb_uart baud=" & integer'image(BAUD) & " suite=" & integer'image(SUITE) & " seed=" & integer'image(SEED) & " clock=75MHz rational ps; bit_ps=" & time'image(BIT_TIME);
    initialize;
    if SUITE=1 then
      -- All values and a random burst at every mismatch/phase combination.
      req<='1';
      for offset_percent in -2 to 2 loop
        if MATRIX_OFFSET=3 or MATRIX_OFFSET=offset_percent then
        duration:=1 sec / (BAUD*(100+offset_percent)/100);
        for phase in 0 to 31 loop
          cycles(3);
          -- Re-align relative to a falling clock, then sweep one clock period.
          wait for phase * 416 ps;
          -- Also vary tick accumulator phase over a nominal oversampling interval.
          wait for (phase * BIT_TIME)/512;
          for value in 0 to 255 loop frame(value,duration); end loop;
          for i in 1 to 32 loop
            random_next(rng); frame(to_integer(rng(7 downto 0)),duration);
          end loop;
          drain; req<='1';
        end loop;
        report "COVER MATRIX mismatch=" & integer'image(offset_percent) & " phases=32 all_bytes=256 random=32";
        end if;
      end loop;
      diagnostics;
    elsif SUITE=2 then
      -- Continuous back-to-back valid traffic, including all patterns.
      req<='1';
      for i in 1 to 10000 loop
        random_next(rng); frame(to_integer(rng(7 downto 0)));
      end loop;
      drain; diagnostics;
      initialize;
      for i in 0 to 599 loop
        frame(i,expect_byte=>i<512);
        if i>=512 then drops:=drops+1; end if;
      end loop;
      cycles(8);
      assert level=512 and full='1' report "512-byte fill" severity failure;
      diagnostics; drain;
      initialize;
      for i in 0 to 399 loop frame(i); end loop;
      cycles(8); assert level=400 report "1ms service interruption" severity failure;
      drain; diagnostics;
      report "COVER THROUGHPUT 10000 continuous; 600 stalled; 1ms service interruption";
    elsif SUITE=3 then
      -- Ten independent seeds are invoked by the runner. Reads change between
      -- frames, making pre-arrival occupancy predictable without DUT byte taps.
      for i in 1 to 10500 loop
        random_next(rng);
        if i mod 3101=0 then
          initialize;
        elsif i mod 2503=0 then
          -- Reset mid-data, with no completed-byte expectation.
          req<='0'; rx<='0'; wait for 4*BIT_TIME;
          rst<='1'; cycles(4); rx<='1'; rst<='0'; cycles(8); wait for BIT_TIME;
          drops:=0; expected_framing:=0; expected_breaks:=0;
        elsif i mod 211=0 then
          rx<='0'; wait for 12*BIT_TIME; rx<='1'; wait for 2*BIT_TIME;
          expected_framing:=expected_framing+1; expected_breaks:=expected_breaks+1;
        elsif i mod 137=0 then
          frame(85,good_stop=>false,expect_byte=>false);
          rx<='1'; wait for BIT_TIME; expected_framing:=expected_framing+1;
        elsif i mod 97=0 then
          rx<='0'; wait for BIT_TIME/8; rx<='1'; wait for BIT_TIME;
        elsif i mod 89=0 then
          clear<='1'; cycles(2); clear<='0';
          drops:=0; expected_framing:=0; expected_breaks:=0;
        else
          -- Long read pauses deliberately drive overflow as well as recovery.
          allow_read:=(i mod 1400)>850 and rng(0)='1';
          req<=bit_value(allow_read); cycles(5); wait for 1 ps;
          accept_byte:=level<512;
          frame(to_integer(rng(15 downto 8)),expect_byte=>accept_byte);
          if not accept_byte then drops:=drops+1; end if;
        end if;
        if i mod 251=0 then diagnostics; end if;
      end loop;
      diagnostics; drain;
      assert completed_frames>=10000 report "Stress frame coverage" severity failure;
      report "COVER STRESS seed=" & integer'image(SEED) & " completed_frames=" & integer'image(completed_frames) & " mixed events and read pauses";
    else
      -- Idle, patterns, variable gaps, false start, framing, break and recovery.
      wait for 20*BIT_TIME; assert level=0 and busy='0' severity failure;
      req<='1';
      for i in 0 to 255 loop
        frame(i); if i mod 17=0 then wait for (i+1)*BIT_TIME/8; end if;
      end loop;
      drain; diagnostics;
      rx<='0'; wait for BIT_TIME/8; rx<='1'; wait for 2*BIT_TIME;
      frame(165); drain; diagnostics;
      frame(85,good_stop=>false,expect_byte=>false);
      rx<='1'; wait for 2*BIT_TIME; expected_framing:=1;
      frame(90); drain; diagnostics;
      rx<='0'; wait for 25*BIT_TIME;
      expected_framing:=2; expected_breaks:=1;
      assert active='1' severity failure;
      diagnostics;
      clear<='1'; cycles(2); clear<='0';
      drops:=0; expected_framing:=0; expected_breaks:=0;
      wait for 12*BIT_TIME; diagnostics;
      assert active='1' report "Clear status interrupted break" severity failure;
      rx<='1'; wait for 2*BIT_TIME; assert active='0' severity failure;
      frame(195); drain; diagnostics;
      -- Release reset into a physical low, including pipeline-fill interval.
      rst<='1'; rx<='0'; cycles(4); rst<='0'; wait for 12*BIT_TIME;
      assert busy='0' and active='1' and fc=0 and bc=1 and level=0
        report "Reset-low arming" severity failure;
      rx<='1'; wait for 2*BIT_TIME; frame(60); drain;
      -- Reset discards queued data and in-flight response.
      initialize; frame(17); cycles(8); assert level=1 severity failure;
      req<='1'; wait until rising_edge(clk); wait for 1 ps;
      assert valid_o='1' severity failure;
      rst<='1'; cycles(2); wait for 1 ps;
      assert valid_o='0' and level=0 severity failure;
      initialize;
      -- Clear status during reception while preserving a previously queued byte.
      frame(34); rx<='0'; wait for BIT_TIME; rx<='1';
      clear<='1'; cycles(2); clear<='0'; wait for 8*BIT_TIME;
      rx<='1'; wait for BIT_TIME; -- frame data FF, stop high
      -- This manually driven valid frame must be expected before draining.
      expected_data<=x"FF"; expected_toggle<=not expected_toggle; cycles(2);
      drain; diagnostics;
      -- Glitches shorter than a system clock cannot guarantee capture. Place
      -- 1ps pulses between clock edges during idle, then verify clean recovery.
      for phase in 1 to 16 loop
        cycles(1); wait for phase*100 ps; rx<='0'; wait for 1 ps; rx<='1';
      end loop;
      wait for 2*BIT_TIME; frame(102); drain; diagnostics;
      report "COVER DIRECTED idle/data/gaps/false-start/framing/break/reset-low/status-clear";
    end if;
    drain;
    report "PASS tb_uart baud=" & integer'image(BAUD) & " suite=" & integer'image(SUITE) & " seed=" & integer'image(SEED);
    finish;
  end process;
  process begin wait for 10 sec; assert false report "UART timeout" severity failure; end process;
end architecture;
