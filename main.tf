provider "aws" {

    region     = "${var.region}"
    access_key = "${var.access_key}"
    secret_key = "${var.secret_key}"
}

resource "aws_dynamodb_table" "dynamodb_table" {
  name = "store_server_details"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "ID"
   attribute {
    name = "ID"
    type = "S"
  }
  stream_enabled = true
  stream_view_type = "NEW_IMAGE"
}

resource "aws_sns_topic" "sns_topic" {
  name = "Invoke_upload_to_table_lambda"
  display_name = "Email Alert - Serverless"
}

resource "aws_sns_topic_subscription" "sns_subscription" {
  topic_arn = aws_sns_topic.sns_topic.arn
  protocol= "email"
  endpoint= var.sns_subscription_email
}


resource "aws_lambda_function" "test_lambda1" {
  filename      = "upload_data_to_DynamoDB.zip"
  function_name = "upload_data_to_DynamoDB"
  role          = "arn:aws:iam::513238944487:role/lambda_role_major"
  handler       = "upload_data_to_DynamoDB.lambda_handler"
  runtime = "python3.9"
  source_code_hash = filebase64sha256("upload_data_to_DynamoDB.zip")
}


resource "aws_lambda_function" "test_lambda2" {
  filename      = "send_email_notification.zip"
  function_name = "send_email_notification"
  role          = "arn:aws:iam::513238944487:role/lambda_role_major"
  handler       = "send_email_notification.lambda_handler"
  runtime = "python3.9"
  source_code_hash = filebase64sha256("send_email_notification.zip")
  environment {
    variables = {
      topic_arn = "${aws_sns_topic.sns_topic.arn}"
    }
  }
}


resource "aws_lambda_event_source_mapping" "lambdatrigger" {
  event_source_arn  = aws_dynamodb_table.dynamodb_table.stream_arn
  function_name     = aws_lambda_function.test_lambda2.arn
  starting_position = "LATEST"
}

########### Creating a Random String ############
resource "random_string" "random" {
  length = 6
  special = false
  upper = false
}

############ Creating an S3 Bucket for uploading ############
resource "aws_s3_bucket" "bucket" {
  bucket = "server-logs-${random_string.random.result}"
  force_destroy = true
}

########### Creating an S3 Bucket for hosting ############
resource "aws_s3_bucket" "bucket2" {
  bucket = "majorwebsite-${random_string.random.result}"
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "example" {
  bucket = aws_s3_bucket.bucket2.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.bucket2.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "example" {
  depends_on = [
    aws_s3_bucket_ownership_controls.example,
    aws_s3_bucket_public_access_block.example,
  ]
  bucket = aws_s3_bucket.bucket2.id
  acl    = "public-read"
}


resource "aws_s3_object" "dist" {
  for_each = fileset("C://Users/Anand/Desktop/task_10118/src", "*")
  bucket = aws_s3_bucket.bucket2.id
  key    = each.value
  source = "C://Users/Anand/Desktop/task_10118/src/${each.value}"
  etag   = filemd5("C://Users/Anand/Desktop/task_10118/src/${each.value}")
  content_type = "text/html"
}

resource "aws_s3_bucket_website_configuration" "example" {
  bucket = aws_s3_bucket.bucket2.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_policy" "example-policy" {
  bucket = aws_s3_bucket.bucket2.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "PublicReadGetObject",
        "Effect": "Allow",
        "Principal": "*",
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::${aws_s3_bucket.bucket2.bucket}/*"
      }
    ]
  }
EOF
}



resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda1.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.test_lambda1.arn
    events= ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.allow_bucket]
}

############## Creating a Cognito Identity Pool ################

resource "aws_cognito_identity_pool" "major_id_pool" {
    identity_pool_name = "${local.cognito_name}"
    allow_unauthenticated_identities = true
}

################# Creating an Cognito IAM Role ################
resource "aws_iam_role" "cognito_unauthenticated_role" {
    name = "cognito_major"
    
    assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "cognito-identity.amazonaws.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "cognito-identity.amazonaws.com:aud": "${aws_cognito_identity_pool.major_id_pool.id}"
                },
                "ForAnyValue:StringLike": {
                    "cognito-identity.amazonaws.com:amr": "unauthenticated"
                }
            }
        }
    ]
}
EOF
}
################# Creating an Cognito Role policy ################

resource "aws_iam_role_policy" "cognito_unauthenticated_policy" {
    name = "cognito_Unauth_policy"
    role = "${aws_iam_role.cognito_unauthenticated_role.id}"
    
    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "mobileanalytics:PutEvents",
                "cognito-sync:*",
                "dynamodb:Scan",
                "dynamodb:GetItem"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF
}

################## Attach Role to Cognito  ######################

resource "aws_cognito_identity_pool_roles_attachment" "main" {
    identity_pool_id = "${aws_cognito_identity_pool.major_id_pool.id}"
    
    roles = {
        "unauthenticated" = "${aws_iam_role.cognito_unauthenticated_role.arn}"
    }
}

