# Description
#   A plugin for group based food ordering.
#
# Dependencies:
#   "<module name>": "<module version>"
#
# Configuration:
#   LIST_OF_ENV_VARS_TO_SET
#
# Commands:
#   hubot start order - Start a group order.
#   hubot start order <text> - Start a group order while filtering through available restaurants with the given text.
#
# Notes:
#   See documentation at github.com/ordrin/hungrybot for examples of how to complete a group order.
#
# Author:
#   ordrin

_ = require 'underscore'
orderUtils = require './orderUtils'
localize = require './localize'

module.exports = (robot) ->

  # A "global" variable containing the state information of the current order.
  HUBOT_APP = {}
  HUBOT_APP.state = 1 #1-listening, 2-Selecting a restaurant 3-gathering orders 4-verify order 5-Placing order

  # Set the initial state of the order.
  initialize = () ->
    # Set the HUBOT_APP to its initial state
    HUBOT_APP.state = 1 #1-listening, 2-Selecting a restaurant 3-gathering orders 4-verify order 5-Placing order
    HUBOT_APP.rid = ""
    HUBOT_APP.users = {} #user state 0 - waiting for order, 1 - waiting for confirmation, 2 - waiting for new request confirmation, 3 - complete
    HUBOT_APP.leader = ''
    HUBOT_APP.restaurants = []
    HUBOT_APP.restaurantLimit = 5

  responseHandlers =
    # Handles any uncaught exceptions.
    error: (err, msg) ->
      console.log err
      if msg?
        console.log err.stack
        console.log msg
        msg.send "Something bad happened! #{err}"

    # Listen for the start of an order.
    startOrder: (msg) ->
      if HUBOT_APP.state is 1
        # A group order has been started
        initialize()
        leader = msg.message.user.name
        HUBOT_APP.leader = leader
        HUBOT_APP.users[leader] = {}
        HUBOT_APP.users[leader].orders = []
        HUBOT_APP.users[leader].state = 0
        msg.send "#{HUBOT_APP.leader} is the leader, and has started a group order. Wait while I find some cool nearby restaurants."

        if msg.match[1].trim() isnt ''
          # A cuisine type or restaurant name was selected.
          HUBOT_APP.keywordString = msg.match[1].trim()
          orderUtils.getRelevantRestaurants msg.match[1].trim(), "ASAP", address, city, zip, 5, (err, data) ->
            if err
              msg.send err
              return err
            if data.length is 0
              msg.send "There were no restaurants that fit that description. Try again."
              return
            HUBOT_APP.restaurants = data
            restaurantsDisplay = ''
            for rest, index in data
              restaurantsDisplay += "(#{index}) #{rest.na}, "
            msg.send "Tell me a restaurant to choose from: #{restaurantsDisplay} (say \"more\" to see more restaurants)"
            HUBOT_APP.filtered = true
            HUBOT_APP.state = 2
        else
          # No particular restaurant or cuisine type was selected.
          orderUtils.getUniqueList 5, (err, data) ->
            if err
              msg.send err
              return err
            HUBOT_APP.restaurants = data
            restaurantsDisplay = ''
            for rest, index in data
              restaurantsDisplay += "(#{index}) #{rest.na}, "
            HUBOT_APP.filtered = false
            msg.send "Tell me a restaurant to choose from: #{restaurantsDisplay} (say \"more\" to see more restaurants)"
            HUBOT_APP.state = 2

    # Displays more options for restaurant or item selection.
    more: (msg) ->
      user = msg.message.user.name
      if user is HUBOT_APP.leader and HUBOT_APP.state is 2
        # Listen for the leader to ask for more restaurants.
        msg.send "Alright let me find more restaurants."
        HUBOT_APP.restaurantLimit += 5
        if HUBOT_APP.filtered
          # A cuisine/restaurant filter was entered.
          orderUtils.getRelevantRestaurants HUBOT_APP.keywordString, "ASAP", address, city, zip, HUBOT_APP.restaurantLimit, (err, data) ->
            if err
              msg.send err
              return err
            HUBOT_APP.restaurants = data
            restaurantsDisplay = ''
            for rest, index in data
              restaurantsDisplay += "(#{index}) #{rest.na}, "
            msg.send "Tell me a restaurant to choose from: #{restaurantsDisplay} (say \"more\" to see more restaurants)"
            HUBOT_APP.state = 2
        else
          # No cuisine/restaurant filter was entered.
          orderUtils.getUniqueList "ASAP", address, city, zip, HUBOT_APP.restaurantLimit, (err, data) ->
            if err
              msg.send err
              return err
            HUBOT_APP.restaurants = data
            restaurantsDisplay = ''
            for rest, index in data
              restaurantsDisplay += "(#{index}) #{rest.na}, "
            msg.send "Tell me a restaurant to choose from: #{restaurantsDisplay} (say \"more\" to see more restaurants)"
            HUBOT_APP.state = 2
      else if HUBOT_APP.state is 3
        # A user asked for more item selections.
        orderDisplay = ''
        orderLimit = HUBOT_APP.users[user].orderLimit
        if orderLimit + 5 < HUBOT_APP.users[user].currentOrders.length
          for order, index in HUBOT_APP.users[user].currentOrders[orderLimit + 1..orderLimit + 5]
            if order?
              orderDisplay += "(#{orderLimit + 1 + index}) #{order.name} - $#{order.price}, "
          msg.send "#{msg.message.user.name} did you mean any of these?: #{orderDisplay} tell me \"no\" if you want something else, and \"more\" to see more options."
          HUBOT_APP.users[user].orderLimit += 5
        else
          msg.send "There are no more matches for that food item. Sorry! Try again."
          HUBOT_APP.users[msg.message.user.name].state = 0

    # Listen for the leader to say that everyone is in.
    finishOrder: (msg) ->
      user = msg.message.user.name
      if user is HUBOT_APP.leader and HUBOT_APP.state is 3
        userString = ''
        _.each HUBOT_APP.users, (user, name) ->
          for order in user.orders
            console.log name
            userString += "#{name}: #{order.name}\n"
        msg.send "Awesome! Lets place this order. Here is what everyone wants:\n #{userString}\nIs this correct? #{HUBOT_APP.leader} tell me \"place order\" when you are ready, and \"no\" if you wish to keep ordering."
        HUBOT_APP.state = 4

    # Listen for users who want to be removed from the order.
    exitOrder: (msg) ->
      user = msg.message.user.name
      if user isnt HUBOT_APP.leader
        HUBOT_APP.users = _.filter HUBOT_APP.users, (userInOrder) -> userInOrder isnt user
        msg.send "I'm sorry to hear that. Looks like #{user} doesn't want to get food with us."

    # Listen for the leader to choose a restaurant, or for a user to select a menu item.
    select: (msg) ->
      username = msg.message.user.name
      message = msg.match[1]
      if not isFinite message
        msgArray = message.split(' ')
        message = msgArray[msgArray.length - 1]

      if HUBOT_APP.state is 2 and username is HUBOT_APP.leader
        # The leader is choosing a restaurant from the given choices.
        if isFinite message
          restaurant = HUBOT_APP.restaurants[message]
          msg.send "Alright lets order from #{restaurant.na}! Everyone enter the name of the item from the menu that you want. #{HUBOT_APP.leader}, tell me when you are done. Tell me \"I'm out\" if you want to cancel your order."
          HUBOT_APP.rid = "#{restaurant.id}"
          HUBOT_APP.state = 3
        else if msg.match[1] in _.pluck HUBOT_APP.restaurants, 'na'
          restaurant = _.findWhere HUBOT_APP.restaurants, na: msg.match[1]
          msg.send "Alright lets order from #{restaurant.na}! Everyone enter the name of the item from the menu that you want. #{HUBOT_APP.leader}, tell me when you are done. Tell me \"I'm out\" if you want to cancel your order."
          HUBOT_APP.rid = "#{restaurant.id}"
          HUBOT_APP.state = 3
        else if message isnt "more"
          msg.send "I didn't get that. Can you try telling me again?"
      else if HUBOT_APP.state is 3
        # User is deciding on which food to get.
        if HUBOT_APP.users[username]?
          if HUBOT_APP.users[username].state is 1
            if isFinite message
              index = message
              console.log index
              HUBOT_APP.users[username].orders.push(HUBOT_APP.users[username].currentOrders[index])
              HUBOT_APP.users[username].state = 2
              msg.send "Cool. #{username} is getting #{HUBOT_APP.users[username].currentOrders[index].name}. #{username}, do you want anything else?"

    # Listen for orders.
    queryMenuItem: (msg) ->
      if isFinite msg.match[1]
        return

      if HUBOT_APP.state is 3
        # A user is asking for a specific type of food.
        user = msg.message.user.name
        if user isnt HUBOT_APP.leader and user not in _.keys(HUBOT_APP.users)
          # This user is just joining the order.
          HUBOT_APP.users[user] = {}
          HUBOT_APP.users[user].state = 0
          HUBOT_APP.users[user].orders = []
          msg.send "Awesome! #{user} is in!"

        if HUBOT_APP.users[user].state in [0, 1, 2]
          order = escape(msg.match[1])

          orderUtils.getRelevantMenuItems(HUBOT_APP.rid, order,
            (err, data) ->
              if err
                console.log err
                msg.send "Sorry I can't find anything like that."
                return err
              console.log data.length

              if data.length > 0
                console.log data.length
                orderDisplay = ''
                for order, index in data
                  orderDisplay += "(#{index}) #{order.name} - $#{order.price}, "
                  if index > 4
                    break
                msg.send "#{msg.message.user.name} did you mean any of these?: #{orderDisplay} tell me \"no\" if you want something else, and \"more\" to see more options."
                HUBOT_APP.users[msg.message.user.name].currentOrders = data
                HUBOT_APP.users[msg.message.user.name].state = 1
                HUBOT_APP.users[msg.message.user.name].orderLimit = 5
              else
                msg.send "Sorry I can't find anything like that. Try again."
          )

    # Listen for confirmation
    confirm: (msg) ->
      username = msg.message.user.name
      if HUBOT_APP.state is 3 and HUBOT_APP.users[username].state is 2
        # The user wants more food.
        msg.send "Wow #{username}, you sure can eat a lot! What do you want?"
        HUBOT_APP.users[username].state = 0

    # Listen for confirmation
    decline: (msg) ->
      username = msg.message.user.name
      if HUBOT_APP.state is 3 and HUBOT_APP.users[username].state is 2
        # This user is finished ordering.
        HUBOT_APP.users[username].state = 3
        msg.send "#{username}, hold on while everyone else orders!"
      else if HUBOT_APP.state is 3 and HUBOT_APP.users[username].state is 1
        # This user does not want any of the suggested items.
        msg.send "Well, #{username} what DO you want then?"
        HUBOT_APP.users[username].state = 0
      else if HUBOT_APP.state is 4
        # The order is not finished yet.
        msg.send "It's all good. I'll keep listening for orders!"
        HUBOT_APP.state = 3

    # Everything is finished, and the order can be placed.
    placeOrder: (msg) ->
      username = msg.message.user.name
      if HUBOT_APP.state is 4 and username is HUBOT_APP.leader
        # confirm and place order
        tray = ''
        _.each HUBOT_APP.users, (user) ->
          for order in user.orders
            tray += "+#{order.tray}"

        params =
          rid: HUBOT_APP.rid
          tray: tray.substring(1)

        msg.send "Placing order. Please wait for me to confirm that everything was correct."
        HUBOT_APP.state = 5
        orderUtils.placeOrder params, (err, data) ->
          if err
            console.log err
            msg.send "Sorry guys! We messed up: #{err.body._msg}"
            HUBOT_APP.state = 1
            return err
          msg.send "Order placed: #{data.msg}"
          HUBOT_APP.state = 1

    # Display orders for each user.
    displayOrders: (msg) ->
      orderDisplay = ''
      for name in _.keys(HUBOT_APP.users)
        user = HUBOT_APP.users[name]
        console.log user
        for order in user.orders
          orderDisplay += "#{name}: #{order.name} - #{order.price}\n"
      msg.send orderDisplay

  # Map listeners to functions.
  mapHandlersToListeners = () ->
    _.each local.listeners, (expressions, name) ->
      for regex in expressions
        robot.respond regex, responseHandlers[name]

  mapHandlersToListeners()
