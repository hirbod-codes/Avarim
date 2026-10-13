# App behavior

## On start up

1. check authentication
   1. if authenticated
      1. fetch user info
      2. fetch avatar if available
      3. set localization preferences in local storage
   2. else
      1. load localization preferences from local storage if exist, otherwise load default localization

## On the web

1. `/` route is a landing page after asking user's preferred language(if not already stored)
   1. if unauthenticated
      1. no nav bar
      2. top bar has a second row of buttons for pricing, about us and contact us pages (users should be able to navigate to these pages(will create them in future))
   2. if authenticated
      1. redirect to `/app`

## on other platforms

1. `/` route doesn't exist
2. user's preferred language and calendar(if not already stored) is asked
3. the client device's timezone is used(if not already stored)
4. user signs up, currently with phone only
5. then redirect user to `/app` page
