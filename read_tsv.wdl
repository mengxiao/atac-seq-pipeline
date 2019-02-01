workflow read_tsv {
	String tsv

	output {
		Array[Array[String]] parsed = read_tsv(tsv)
	}
}