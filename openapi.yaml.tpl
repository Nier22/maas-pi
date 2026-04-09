swagger: "2.0"
info:
  title: maas-api
  version: 1.0.0
schemes:
  - https
paths:
  /estimate_pi:
    post:
      operationId: estimatePi
      consumes:
        - application/json
      produces:
        - application/json
      parameters:
        - in: body
          name: body
          required: true
          schema:
            type: object
            properties:
              total_points:
                type: integer
      responses:
        "202":
          description: Accepted
      x-google-backend:
        address: ${backend_url}
        path_translation: APPEND_PATH_TO_ADDRESS