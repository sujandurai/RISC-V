# Phase 2: Accelerator Source Audit

## Original Accelerator File List
The following original files were obtained from the user's uploaded `rtl` directory:
- `accelerator_top.v`
- `activation_buffer.v`
- `controller.v`
- `data_path.v`
- `output_buffer.v`
- `pe.v`
- `skew.v`
- `systolic_8x8.v`
- `weight_buffer.v`

## SHA-256 Hashes
These hashes serve as proof that the supplied fixed IP is completely unmodified:
- `accelerator_top.v`: DBAB334DF1D5F792881A9F5D579AB686FB1B29B5BF904BB0E868185496D9D9A8
- `activation_buffer.v`: 00D29D02FA7A1177672BEB4126953A847258C9299E8821BF84E177D96E34983D
- `controller.v`: 660595E48FACD7116AFFD1F90C44D0D3212CE5CC8A7665E238D95CB8AC581719
- `data_path.v`: DA2913ADF78772C3EC3F719074B5DDE18DC77C48E9B7F7CE2A07CA791A4E695B
- `output_buffer.v`: 7FBB95BFA4209FA20CC77E51F84FF0F85BCD09C2FBF51267D42CE6CE19C7950B
- `pe.v`: 61555AB09CB4311D4773DEDB43FCD1CCD8C77AD2DF0830FEAE5DF3657E2EB172
- `skew.v`: 2D9FAA0899A7BD1F86EB0A1A5AE4D913F0988AA613C7A08DC35DF400F3C13C70
- `systolic_8x8.v`: CA9285BC673D01C88BFFB31836A4CF567B1A5BCB1691F6EB5A88735D6BBBA42E
- `weight_buffer.v`: 711EAA405E084442CF7E20E4DA1A678E5B426802F53E072E943BCF92428624EA

## Audit Findings
- **Exact top module**: `accelerator`
- **Exact module parameters**: `DW = 8`, `AW = 32`
- **Exact top-level ports**: `clk`, `rst_n`, `start`, `busy`, `done`, `wr_en`, `matrix_select`, `wr_row[2:0]`, `wr_col[2:0]`, `wr_data[DW-1:0]`, `rd_en`, `rd_addr[5:0]`, `rd_data[AW-1:0]`, `rd_valid`
- **Clock**: `clk` (synchronous)
- **Reset polarity and style**: `rst_n` (active-low, synchronous, used in `always @(posedge clk)`)
- **Start behavior**: `start` input, single-cycle assertion
- **Busy behavior**: `busy` output, asserted during execution
- **Done behavior**: `done` output, asserted for exactly 1 cycle at the end of the operation sequence
- **Write enable behavior**: `wr_en` writes a single element per cycle. 
- **Matrix select behavior**: `matrix_select` (0 = Activation A, 1 = Weight B)
- **Row field**: `wr_row[2:0]`
- **Column field**: `wr_col[2:0]`
- **Input data width**: `DW=8` (INT8)
- **Result read address**: `rd_addr[5:0]`
- **Result read enable**: `rd_en`
- **Result data**: `rd_data[AW-1:0]` (INT32)
- **Result-valid behavior**: `rd_valid` is asserted with a 1-cycle latency relative to `rd_en`
- **Result ordering**: The memory in `output_buffer.v` correctly maps `rd_addr[5:3]` to row and `rd_addr[2:0]` to column. Thus, `rd_addr = 8*row + col`, which is standard row-major ordering.
- **Operand storage behavior**: Memory elements loaded individually via `wr_en`.
- **Weight retention behavior**: Weight data resides in the buffers across iterations until explicitly overwritten.
- **Controller sequence**: Start -> Read weights from weight buffer -> Load weights into PEs -> Stream activations and compute -> Capture outputs diagonally -> Assert `done`.
- **Fixed K semantics**: Inner loop operates on $K=8$.
- **Reset effects**: Clears all valid states and internal buffers synchronously.
- **Timing-sensitive behavior**: `rd_valid` relies on a synchronous 1-cycle pipeline delay; firmware wrappers must handle this latency correctly.

## Conclusion
The fixed IP matches the v4.0 specification perfectly. No structural modifications or adjustments to the fixed RTL are required. The integration wrapper will be built strictly around the defined boundary.
