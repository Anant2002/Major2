output "table_arn1" {

    value = aws_dynamodb_table.dynamodb_table.arn
    description = "DynamoDB Table created successfully"
}

output "topic_arn1" {

    value = aws_sns_topic.sns_topic.arn
    description = "Topic created successfully"

}

output "website_endpoint" {
  value = "http://${aws_s3_bucket.bucket2.website_endpoint}/?pool_id=${aws_cognito_identity_pool.major_id_pool.id}&table_name=store_server_details"
}

