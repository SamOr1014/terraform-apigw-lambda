import json

def lambda_handler(event, context):
    name = event["queryStringParameters"]["name"] or "Default"
    message = f'Hello Welcome {name}!'
    return {
        "statusCode": 200,
        "body": json.dumps({
        "message" : message
        }),
        "headers": {
            "content-type": "application/json"
        }
    }   