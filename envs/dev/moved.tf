moved {
  from = aws_instance.kafka
  to   = aws_instance.kafka[0]
}

moved {
  from = aws_volume_attachment.kafka_data
  to   = aws_volume_attachment.kafka_data[0]
}

moved {
  from = aws_service_discovery_instance.kafka
  to   = aws_service_discovery_instance.kafka[0]
}

moved {
  from = aws_security_group_rule.alb_to_tasks["admin"]
  to   = aws_security_group_rule.alb_to_tasks["80"]
}

moved {
  from = aws_security_group_rule.alb_to_tasks["control"]
  to   = aws_security_group_rule.alb_to_tasks["8081"]
}

moved {
  from = aws_security_group_rule.alb_to_tasks["dispatch"]
  to   = aws_security_group_rule.alb_to_tasks["8082"]
}

moved {
  from = aws_security_group_rule.alb_to_tasks["relocation"]
  to   = aws_security_group_rule.alb_to_tasks["8083"]
}

moved {
  from = aws_security_group_rule.alb_to_tasks["user"]
  to   = aws_security_group_rule.alb_to_tasks["8084"]
}
