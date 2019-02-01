workflow read_map {
	String map_file

	output {
		Map[String,String] map = read_map(map_file)
	}
}