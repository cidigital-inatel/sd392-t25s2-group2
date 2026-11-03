# Execute depois de vivado_add_all_sources.tcl, para selecionar o teste do Parser.
set_property top tb_packet_parser_pcap [get_filesets sim_1]
update_compile_order -fileset sim_1
puts "Top de simulacao selecionado: tb_packet_parser_pcap"
