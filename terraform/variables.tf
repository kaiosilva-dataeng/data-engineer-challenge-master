variable "glue_tables" {
  description = "Um mapa de tabelas a serem criadas no Glue, com seus schemas e partições."
  type = map(object({
    columns = list(object({
      name = string
      type = string
    }))
    partition_keys = list(object({
      name = string
      type = string
    }))
  }))
  default = {}
}