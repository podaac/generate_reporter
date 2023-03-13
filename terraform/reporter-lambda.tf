# AWS Lambda function
resource "aws_lambda_function" "aws_lambda_reporter" {
  image_uri     = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.prefix}-reporter:latest"
  function_name = "${var.prefix}-reporter"
  role          = aws_iam_role.aws_lambda_reporter_execution_role.arn
  package_type  = "Image"
  memory_size   = 256
  timeout       = 900
}

# AWS Lambda execution role & policy
resource "aws_iam_role" "aws_lambda_reporter_execution_role" {
  name = "${var.prefix}-lambda-reporter-execution-role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  permissions_boundary = "arn:aws:iam::${local.account_id}:policy/NGAPShRoleBoundary"
}

resource "aws_iam_role_policy_attachment" "aws_lambda_reporter_execution_role_policy_attach" {
  role       = aws_iam_role.aws_lambda_reporter_execution_role.name
  policy_arn = aws_iam_policy.aws_lambda_reporter_execution_policy.arn
}

resource "aws_iam_policy" "aws_lambda_reporter_execution_policy" {
  name        = "${var.prefix}-lambda-reporter-execution-policy"
  description = "Publish to report and failure SNS Topics."
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowCreatePutLogs",
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "arn:aws:logs:*:*:*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "sns:ListTopics"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "sns:Publish"
        ],
        "Resource" : [
          "${data.aws_sns_topic.batch_failure_topic.arn}",
          "${aws_sns_topic.aws_sns_topic_reporter.arn}"
        ]
      }
    ]
  })
}

# SNS Topic Report
resource "aws_sns_topic" "aws_sns_topic_reporter" {
  name         = "${var.prefix}-reporter"
  display_name = "${var.prefix}-reporter"
}

resource "aws_sns_topic_policy" "aws_sns_topic_reporter_policy" {
  arn = aws_sns_topic.aws_sns_topic_reporter.arn
  policy = jsonencode({
    "Version" : "2008-10-17",
    "Id" : "__default_policy_ID",
    "Statement" : [
      {
        "Sid" : "__default_statement_ID",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "*"
        },
        "Action" : [
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish"
        ],
        "Resource" : "${aws_sns_topic.aws_sns_topic_reporter.arn}",
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceOwner" : "${local.account_id}"
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "aws_sns_topic_reporter_subscription" {
  endpoint  = var.sns_topic_email
  protocol  = "email"
  topic_arn = aws_sns_topic.aws_sns_topic_reporter.arn
}

# EventBridge schedule
resource "aws_scheduler_schedule" "aws_schedule_reporter" {
  name       = "${var.prefix}-reporter"
  group_name = "default"
  flexible_time_window {
    mode = "OFF"
  }
  schedule_expression = "cron(55 23 * * ? *)"
  target {
    arn      = aws_lambda_function.aws_lambda_reporter.arn
    role_arn = aws_iam_role.aws_eventbridge_reporter_execution_role.arn
  }
}

# EventBridge execution role and policy
resource "aws_iam_role" "aws_eventbridge_reporter_execution_role" {
  name = "${var.prefix}-eventbridge-reporter-execution-role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "scheduler.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  permissions_boundary = "arn:aws:iam::${local.account_id}:policy/NGAPShRoleBoundary"
}

resource "aws_iam_role_policy_attachment" "aws_eventbridge_reporter_execution_role_policy_attach" {
  role       = aws_iam_role.aws_eventbridge_reporter_execution_role.name
  policy_arn = aws_iam_policy.aws_eventbridge_reporter_execution_policy.arn
}

resource "aws_iam_policy" "aws_eventbridge_reporter_execution_policy" {
  name        = "${var.prefix}-eventbridge-reporter-execution-policy"
  description = "Allow EventBridge to invoke a Lambda function."
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowInvokeLambda",
        "Effect" : "Allow",
        "Action" : [
          "lambda:InvokeFunction"
        ],
        "Resource" : "${aws_lambda_function.aws_lambda_reporter.arn}"
      }
    ]
  })
}