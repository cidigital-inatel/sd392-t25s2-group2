# Execute depois de vivado_add_all_sources.tcl, para selecionar a integracao completa.
set_property top tb_pcap_to_features [get_filesets sim_1]
update_compile_order -fileset sim_1
puts "Top de simulacao selecionado: tb_pcap_to_features"
