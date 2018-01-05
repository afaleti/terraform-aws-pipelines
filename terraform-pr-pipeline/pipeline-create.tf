/**
  Resources for the pipeline-create lambda function
 */

resource "aws_lambda_function" "pipeline_create" {
  depends_on       = ["null_resource.pipeline_create_dependencies"]
  filename         = ".lambda-zip/pipeline-create.zip"
  function_name    = "${var.project_name}-pipeline-create"
  role             = "${aws_iam_role.pipeline_create.arn}"
  handler          = "pipeline-create.lambda_handler"
  source_code_hash = "${base64sha256(file("${path.module}/.lambda-zip/pipeline-create.zip"))}"
  runtime          = "python3.6"

  tags {
    Name = "${var.project_name}-pipeline-create"
  }

  environment {
    variables = {
      # GITHUB_PAC           = "${var.github_pac}"
      GITHUB_API_URL         = "${var.github_api_url}"
      GITHUB_REPO_NAME       = "${var.github_repo_name}"
      BUCKET_NAME            = "${aws_s3_bucket.bucket.id}"
      PROJECT_NAME           = "${var.project_name}"
      CODE_BUILD_IMAGE       = "${var.code_build_image}"
      TERRAFORM_DOWNLOAD_URL = "${var.terraform_download_url}"

      CODEBUILD_SERVICE_ROLE    = "${var.codebuild_iam_service_role_arn}"
      CODEPIPELINE_SERVICE_ROLE = "${var.codepipeline_iam_service_role_arn}"
    }
  }
}

// Allows s3 to trigger the function
resource "aws_lambda_permission" "pipeline_create" {
  statement_id  = "schedule"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.pipeline_create.function_name}"
  principal     = "s3.amazonaws.com"
  source_arn    = "${aws_s3_bucket.bucket.arn}"
}

// Creates zip file with dependencies every time pipeline-create.py is updated
resource "null_resource" "pipeline_create_dependencies" {
  triggers {
    lambda_function = "${file("${path.module}/pipeline-create/pipeline-create.py")}"
  }

  provisioner "local-exec" {
    command = "rm -rf ${path.module}/.lambda-zip/pipeline-create-resources"
  }

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/.lambda-zip/pipeline-create-resources"
  }

  provisioner "local-exec" {
    command = "pip install --target=${path.module}/.lambda-zip/pipeline-create-resources requests"
  }

  provisioner "local-exec" {
    command = "cp -R ${path.module}/pipeline-create/pipeline-create.py ${path.module}/.lambda-zip/pipeline-create-resources/."
  }

  provisioner "local-exec" {
    command = "cp -R ${path.module}/pipeline-create/*.yml ${path.module}/.lambda-zip/pipeline-create-resources/."
  }

  provisioner "local-exec" {
    command = "cd ${path.module}/.lambda-zip/pipeline-create-resources/ && zip -r ../pipeline-create.zip ."
  }
}

// AWS IAM role for pipeline-create function
resource "aws_iam_role" "pipeline_create" {
  name               = "${var.project_name}-pipeline-create-lambda"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role.json}"
}

data "aws_iam_policy_document" "pipeline_create" {
  statement {
    sid = "CreateLogs"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-pipeline-create:*",
    ]
  }

  statement {
    sid = "CodeBuildAccess"

    actions = [
      "codebuild:CreateProject",
    ]

    resources = [
      "arn:aws:codebuild:${var.aws_region}:${data.aws_caller_identity.current.account_id}:project/${var.project_name}*",
    ]
  }

  statement {
    sid = "CodePipelineAccess"

    actions = [
      "codepipeline:GetPipeline",
      "codepipeline:CreatePipeline",
    ]

    resources = [
      "arn:aws:codepipeline:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.project_name}*",
    ]
  }

  statement {
    sid = "iam"

    actions = [
      "iam:PassRole",
    ]

    resources = [
      "${var.codepipeline_iam_service_role_arn}",
      "${var.codebuild_iam_service_role_arn}",
    ]
  }
}

resource "aws_iam_policy" "pipeline_create" {
  name   = "${aws_iam_role.pipeline_create.name}-policy"
  policy = "${data.aws_iam_policy_document.pipeline_create.json}"
}

resource "aws_iam_role_policy_attachment" "pipeline_create" {
  role       = "${aws_iam_role.pipeline_create.name}"
  policy_arn = "${aws_iam_policy.pipeline_create.arn}"
}