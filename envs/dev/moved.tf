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
