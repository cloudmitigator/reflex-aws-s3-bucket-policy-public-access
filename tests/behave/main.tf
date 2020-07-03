terraform {
  backend "s3" {
    bucket = "reflex-state"
    key    = "reflex-s3-bucket-policy-public-access"
  }
}

data "aws_caller_identity" "current" {}

module "s3-bucket-policy-public-access-cwe" {
  source = "../../terraform/cwe"
}

module "s3-bucket-policy-public-access" {
  source                    = "../../terraform/sqs_lambda"
  cloudwatch_event_rule_id  = module.s3-bucket-policy-public-access-cwe.id
  cloudwatch_event_rule_arn = module.s3-bucket-policy-public-access-cwe.arn
  sns_topic_arn             = module.central-sns-topic.arn
  reflex_kms_key_id         = module.reflex-kms-key.key_id
}

module "central-sns-topic" {
  topic_name         = "ReflexAlerts"
  stack_name         = "EmailSNSStackReflexAlerts"
  source             = "git::https://github.com/cloudmitigator/reflex-engine.git//modules/sns_email_subscription?ref=v0.6.0"
  notification_email = "richard.julian@cloudmitigator.com"
}

module "reflex-kms-key" {
  source = "git::https://github.com/cloudmitigator/reflex-engine.git//modules/reflex_kms_key?ref=v0.6.0"
}

resource "aws_sqs_queue" "test_queue" {
  name          = "test-queue"
  delay_seconds = 0
}

resource "aws_sqs_queue_policy" "test_queue_policy" {
  queue_url = aws_sqs_queue.test_queue.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
   {
      "Sid": "AllowSNSTopic",
      "Effect": "Allow",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": "sqs:SendMessage",
      "Resource": "${aws_sqs_queue.test_queue.arn}"
    },
   {
      "Sid": "AllowUserAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${data.aws_caller_identity.current.arn}"
      },
      "Action": "sqs:ReceiveMessage",
      "Resource": "${aws_sqs_queue.test_queue.arn}"
    }
  ]
}
POLICY
}

resource "aws_sns_topic_subscription" "test_queue_target" {
  topic_arn = module.central-sns-topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.test_queue.arn
}


