//
//  MatchHelper.swift
//  Warfare
//
//  Created by Justin Domingue on 2015-02-16.
//  Copyright (c) 2015 Justin Domingue. All rights reserved.
//

import Foundation
import GameKit

private var sharedHelper: MatchHelper?

class MatchHelper: NSObject, GKTurnBasedMatchmakerViewControllerDelegate, GKLocalPlayerListener {
    var gameCenterAvailable: Bool {
        // Check for presence of GKLocalPlayer API
        let gClass: AnyClass? = NSClassFromString("GKLocalPlayer")

        // NOTE: No need to check if device is iOS 4.1 or higher
        return gClass != nil
    }
    var userAuthenticated = false

    var vc: UIViewController?
    var myMatch: GKTurnBasedMatch?

    override init() {
        super.init()

        if self.gameCenterAvailable {
            let nc = NSNotificationCenter.defaultCenter()
            nc.addObserver(self, selector: Selector("authenticationChanged"), name:GKPlayerAuthenticationDidChangeNotificationName, object: nil)
        }

    }

    class func sharedInstance() -> MatchHelper {
        if sharedHelper == nil {
            sharedHelper = MatchHelper()
        }

        return sharedHelper!
    }

    func currentParticipantIndex() -> Int {
        let participants: [GKTurnBasedParticipant] = self.myMatch?.participants as [GKTurnBasedParticipant]

        for (index, p) in enumerate(participants) {
            if p === self.myMatch?.currentParticipant {
                return index
            }
        }

        // fallback
        return 0
    }

    // MARK: - Authentication

    func authenticateLocalUser() {
        if !gameCenterAvailable { return }

        if !GKLocalPlayer.localPlayer().authenticated {
            var localPlayer = GKLocalPlayer.localPlayer()
            localPlayer.authenticateHandler = {(viewController : UIViewController!, error : NSError!) -> Void in
                if ((viewController) != nil) {
                    self.vc?.presentViewController(viewController, animated: true, completion: nil)
                }else{
                    self.userAuthenticated = true
                }
            }
        }
    }

    func authenticationChanged() {
        if GKLocalPlayer.localPlayer().authenticated && !self.userAuthenticated {
            self.userAuthenticated = true
            GKLocalPlayer.localPlayer().unregisterAllListeners()
            GKLocalPlayer.localPlayer().registerListener(self)
            println("Registered GKLocalPlayer listener")
        } else if !GKLocalPlayer.localPlayer().authenticated && self.userAuthenticated {
            self.userAuthenticated = false
        }
    }

    // MARK: - GKMatch

    func joinMatch() {
        if self.userAuthenticated {
            // Create match request
            let request = GKMatchRequest()
            request.minPlayers = 3
            request.maxPlayers = 3
            request.defaultNumberOfPlayers = 3


            let mmvc = GKTurnBasedMatchmakerViewController(matchRequest: request)
            mmvc.turnBasedMatchmakerDelegate = self

            self.vc?.presentViewController(mmvc, animated: true, completion: nil)
        }
    }

    func loadMatchData() {
        self.myMatch?.loadMatchDataWithCompletionHandler({ (matchData: NSData!, error: NSError!) -> Void in
            // Delegate match decoding to GameEngine
            GameEngine.Instance.decode(matchData)
        })
    }

    // If the player takes an action that is irrevocable
    // (but control is not yet passed to another player),
    // encode the updated match data and send it to Game Center
    //
    func updateMatchData() {
        let updatedMatchData = GameEngine.Instance.encodeMatchData()

        self.myMatch?.saveCurrentTurnWithMatchData(updatedMatchData, completionHandler: {(error: NSError!) -> Void in
            if ((error) != nil) {
                println(error)
            }
        })
    }

    //  Te current player takes an action that either ends
    //  the match or requires another participant to act
    //  NOTE: the function takes care of extracting the match data
    func advanceMatchTurn() {
        if let match = self.myMatch {

            let updatedMatchData = GameEngine.Instance.encodeMatchData()
            match.message = GameEngine.Instance.encodeTurnMessage()

            match.endTurnWithNextParticipants(nextParticipants(), turnTimeout: GKTurnTimeoutDefault, matchData: updatedMatchData, completionHandler: {(error: NSError!) -> Void in
                if ((error) != nil) {
                    println(error)
                }
            })

        }
    }

    // The current player has selected a map
    // NOTE: the function requires match data
    func advanceSelectionTurn(data: NSData) {
        if let match = self.myMatch {
            match.endTurnWithNextParticipants(nextParticipants(), turnTimeout: GKTurnTimeoutDefault, matchData: data, completionHandler: {(error: NSError!) -> Void in
                if ((error) != nil) {
                    println(error)
                }
            })
        }
    }

    // TODO also take care of match outcome
    func nextParticipants(current: Int) -> NSArray {
        // Too pretty to eliminate
        //        var playing = [GKTurnBasedParticipant]()
        //        var eliminated = [GKTurnBasedParticipant]()
        //
        //        self.myMatch?.participants.map({($0.matchOutcome == .None) ? playing.append($0) : eliminated.append($0)})

        let nextParticipants = NSMutableArray(capacity: 3)
        nextParticipants[0] = (self.myMatch?.participants[(current+1)%3])!
        nextParticipants[1] = (self.myMatch?.participants[(current+2)%3])!
        nextParticipants[2] = (self.myMatch?.participants[current])! // should be current participant
        return nextParticipants
    }

    func nextParticipants() -> NSArray {
        return self.nextParticipants(self.currentParticipantIndex())
    }

    func removeParticipant(index: Int) {
        // Retrieve participant and set match outcome to lost
        let p = self.myMatch?.participants[index] as GKTurnBasedParticipant
        p.matchOutcome = GKTurnBasedMatchOutcome.Lost

        // End the match if 2 participant have lost
        if !didEndMatch() {
            // Send the update to Game Center
            self.updateMatchData()
        }
    }

    func didEndMatch() -> Bool {
        // End the match if 2 participant have lost
        if let m = self.myMatch {
            if (m.participants.reduce(0) {$0 + ($1.matchOutcome == .None ? 0 : 1) }) == 2 {
                self.endMatch()
                return true
            }
        }

        return false
    }

    // TODO right now, called only after removeParticipant() but not player quit
    func endMatch() {
        let finalMatchData = GameEngine.Instance.encodeMatchData()
        self.myMatch?.endMatchInTurnWithMatchData(finalMatchData, completionHandler: {(error: NSError!) -> Void in})
    }

    // Mark: - GKTurnBasedMatchViewControllerDelegate

    func turnBasedMatchmakerViewControllerWasCancelled(controller: GKTurnBasedMatchmakerViewController!) {
        self.vc?.dismissViewControllerAnimated(true, completion: nil)
    }

    func turnBasedMatchmakerViewController(controller: GKTurnBasedMatchmakerViewController!, didFindMatch match: GKTurnBasedMatch!) {
        self.myMatch = match
        self.loadMatchData()
    }

    func turnBasedMatchmakerViewController(controller: GKTurnBasedMatchmakerViewController!, playerQuitForMatch match: GKTurnBasedMatch!) {

        let participants = match.participants!

        // Make next participant array
        var nextParticipants = [GKTurnBasedParticipant]()
        for p in participants {
            if p.playerID! != nil && p.playerID! == GKLocalPlayer.localPlayer().playerID {
                nextParticipants.append(p as GKTurnBasedParticipant)
            } else if p.matchOutcome == .None {
                nextParticipants.insert(p as GKTurnBasedParticipant, atIndex: 0)
            }
        }

        // Send quit
        // TODO matchData mught not be the most up to date
        match.participantQuitInTurnWithOutcome(.Quit, nextParticipants: nextParticipants, turnTimeout: GKTurnTimeoutDefault, matchData: match.matchData, completionHandler: ({(e: NSError!) in println(e)}))
    }

    func turnBasedMatchmakerViewController(controller: GKTurnBasedMatchmakerViewController!, didFailWithError: NSError!) {
        self.vc?.dismissViewControllerAnimated(true, completion: nil)
    }

    // Mark: - GKTurnBasedEventListener

    // Mark: Handling Exchanges
    func player(player: GKPlayer!, receivedExchangeCancellation exchange: GKTurnBasedExchange!, forMatch match: GKTurnBasedMatch!) {
        // Do nothing
    }

    func player(player: GKPlayer!, receivedExchangeReplies replies: GKTurnBasedExchange!, forCompletedExchange exchange: GKTurnBasedExchange!,forMatch match: GKTurnBasedMatch!) {
        // Do nothing
    }

    func player(player: GKPlayer!,
        receivedExchangeRequest exchange: GKTurnBasedExchange!,
        forMatch match: GKTurnBasedMatch!) {
            // Do nothing
    }

    // Mark: Handling Match Related Events

    func player(player: GKPlayer!,
        didRequestMatchWithOtherPlayers playersToInvite: [AnyObject]!) {

    }

    func player(player: GKPlayer!,
        matchEnded match: GKTurnBasedMatch!) {

    }

    func player(player: GKPlayer!,
        receivedTurnEventForMatch match: GKTurnBasedMatch!,
        didBecomeActive: Bool) {
            self.myMatch = match
            self.loadMatchData()

            // TODO if we want to handle the case where the appp was not opened
            // then we'd want to pass didBecomeActive to the GameEngine so it
            // can take care of showing the controller
            /*if didBecomeActive {
                if let mmvc = self.vc as? MainMenuViewController {
                    mmvc.segueToGameViewController()
                } else { println("huh... current view controller should be MainMenuViewController but is" + (self.vc?.description)!) }
            }*/
    }
}
