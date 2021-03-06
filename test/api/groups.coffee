'use strict'

diff = require("deep-diff")

Group = require("../../website/src/models/group").model
app = require("../../website/src/server")

describe "Guilds", ->
  before (done) ->
    registerNewUser ->
      User.findByIdAndUpdate user._id,
        $set:
          "balance": 10
        , (err, _user) ->
          done()
    , true

  context "creating groups", ->
    it "can create a public guild", (done) ->
      request.post(baseURL + "/groups").send(
        name: "TestGroup"
        type: "guild",
        privacy: "public"
      ).end (res) ->
        expectCode res, 200
        guild = res.body
        expect(guild.members.length).to.equal 1
        expect(guild.leader).to.equal user._id
        done()

    it "can create a private guild", (done) ->
      request.post(baseURL + "/groups").send(
        name: "TestGroup"
        type: "guild",
        privacy: "private"
      ).end (res) ->
        expectCode res, 200
        guild = res.body
        expect(guild.members.length).to.equal 1
        expect(guild.leader).to.equal user._id
        done()

    it "prevents user from creating a guild when the user has 0 gems", (done) ->
      registerNewUser (err, user_with_0_gems) ->
        request.post(baseURL + "/groups").send(
            name: "TestGroup"
            type: "guild",
        )
        .set("X-API-User", user_with_0_gems._id)
        .set("X-API-Key", user_with_0_gems.apiToken)
        .end (res) ->
          expectCode res, 401
          done()
      , false

  context "finding groups", ->
    it "can find a guild", (done) ->
      guild = undefined
      request.post(baseURL + "/groups").send(
        name: "TestGroup2"
        type: "guild"
      ).end (res) ->
        guild = res.body
        request.get(baseURL + "/groups/" + guild._id)
        .send()
        .end (res) ->
          expectCode res, 200
          expect(guild._id).to.equal res.body._id
          done()

    it "can list guilds", (done) ->
      request.get(baseURL + "/groups").send()
      .end (res) ->
        expectCode res, 200
        guild = res.body[0]
        expect(guild).to.exist
        done()

  context "updating groups", ->
    groupToUpdate = undefined
    before (done) ->
      request.post(baseURL + "/groups").send(
        name: "TestGroup"
        type: "guild"
        description: "notUpdatedDesc"
      ).end (res) ->
        groupToUpdate = res.body
        done()

    it "prevents user from updating a party when they aren't the leader", (done) ->
      registerNewUser (err, tmpUser) ->
        request.post(baseURL + "/groups/" + groupToUpdate._id).send(
            name: "TestGroupName"
            description: "updatedDesc"
        )
        .set("X-API-User", tmpUser._id)
        .set("X-API-Key", tmpUser.apiToken)
        .end (res) ->
          expectCode res, 401
          expect(res.body.err).to.equal "Only the group leader can update the group!"
          done()
      , false

    it "allows user to update a group", (done) ->
      request.post(baseURL + "/groups/" + groupToUpdate._id).send(
          description: "updatedDesc"
      )
      .end (res) ->
        expectCode res, 204
        request.get(baseURL + "/groups/" + groupToUpdate._id).send()
        .end (res) ->
          updatedGroup = res.body
          expect(updatedGroup.description).to.equal "updatedDesc"
          done()

  context "leaving groups", ->
    it "can leave a guild", (done) ->
      guildToLeave = undefined
      request.post(baseURL + "/groups").send(
        name: "TestGroupToLeave"
        type: "guild"
      ).end (res) ->
        guildToLeave = res.body
        request.post(baseURL + "/groups/" + guildToLeave._id + "/leave")
        .send()
        .end (res) ->
          expectCode res, 204
          done()

  context "removing users groups", ->
    it "allows guild leaders to remove a member", (done) ->
      guildToRemoveMember = undefined
      members = undefined
      userToRemove = undefined
      request.post(baseURL + "/groups").send(
        name: "TestGuildToRemoveMember"
        type: "guild"
      ).end (res) ->
        guildToRemoveMember = res.body
        #Add members to guild
        async.waterfall [
          (cb) ->
            registerManyUsers 1, cb

          (_members, cb) ->
            userToRemove = _members[0]
            members = _members
            inviteURL = baseURL + "/groups/" + guildToRemoveMember._id + "/invite"
            request.post(inviteURL).send(
              uuids: [userToRemove._id]
            )
            .end ->
              cb()

          (cb) ->
            request.post(baseURL + "/groups/" + guildToRemoveMember._id + "/join")
              .set("X-API-User", userToRemove._id)
              .set("X-API-Key", userToRemove.apiToken)
              .end (res) ->
                cb()

          (cb) ->
            request.post(baseURL + "/groups/" + guildToRemoveMember._id + "/removeMember?uuid=" + userToRemove._id)
            .send().end (res) ->
              expectCode res, 204
              cb()

          (cb) ->
            request.get(baseURL + "/groups/" + guildToRemoveMember._id)
            .send()
            .end (res) ->
              g = res.body
              userInGroup = _.find g.members, (member) -> return member._id == userToRemove._id
              expect(userInGroup).to.not.exist
              cb()

        ], done

  describe "Private Guilds", ->
    guild = undefined
    before (done) ->
      request.post(baseURL + "/groups").send(
        name: "TestPrivateGroup"
        type: "guild"
        privacy: "private"
      ).end (res) ->
        expectCode res, 200
        guild = res.body
        expect(guild.members.length).to.equal 1
        expect(guild.leader).to.equal user._id
        #Add members to guild
        async.waterfall [
          (cb) ->
            registerManyUsers 15, cb

          (_members, cb) ->
            members = _members

            joinGuild = (member, callback) ->
              request.post(baseURL + "/groups/" + guild._id + "/join")
                .set("X-API-User", member._id)
                .set("X-API-Key", member.apiToken)
                .end ->
                  callback(null, null)

            async.map members, joinGuild, (err, results) -> cb()

        ], done

    it "includes user in private group member list when user is a member", (done) ->

      request.get(baseURL + "/groups/" + guild._id)
      .end (res) ->
        g = res.body
        userInGroup = _.find g.members, (member) -> return member._id == user._id
        expect(userInGroup).to.exist
        done()

    it "excludes user from viewing private group member list when user is not a member", (done) ->

      request.post(baseURL + "/groups/" + guild._id + "/leave")
        .end (res) ->
          request.get(baseURL + "/groups/" + guild._id)
          .end (res) ->
            expect res, 404
            done()

  describe "Public Guilds", ->
    guild = undefined
    before (done) ->
      request.post(baseURL + "/groups").send(
        name: "TestPublicGroup"
        type: "guild"
        privacy: "public"
      ).end (res) ->
        expectCode res, 200
        guild = res.body
        expect(guild.members.length).to.equal 1
        expect(guild.leader).to.equal user._id
        #Add members to guild
        async.waterfall [
          (cb) ->
            registerManyUsers 15, cb

          (_members, cb) ->
            members = _members

            joinGuild = (member, callback) ->
              request.post(baseURL + "/groups/" + guild._id + "/join")
                .set("X-API-User", member._id)
                .set("X-API-Key", member.apiToken)
                .end ->
                  callback(null, null)

            async.map members, joinGuild, (err, results) -> cb()
        ], done

    context "is a member", ->
      before (done) ->
        registerNewUser ->
          request.post(baseURL + "/groups/" + guild._id + "/join")
            .end ->
              done()
        , true

      it "includes user in public group member list", (done) ->
        request.get(baseURL + "/groups/" + guild._id)
          .end (res) ->
            g = res.body
            expect(g.members.length).to.equal 15
            userInGroup = _.find g.members, (member) -> return member._id == user._id
            expect(userInGroup).to.exist
            done()


    context "is not a member", ->
      before (done) ->
        registerNewUser done, true

      it "excludes user in public group member list", (done) ->
        request.get(baseURL + "/groups/" + guild._id)
          .end (res) ->
            g = res.body
            expect(g.members.length).to.equal 15
            userInGroup = _.find g.members, (member) -> return member._id == user._id
            expect(userInGroup).to.not.exist
            done()
