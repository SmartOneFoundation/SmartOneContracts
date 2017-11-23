pragma solidity ^0.4.15;
import "./zeppelin-solidity/contracts/ownership/Ownable.sol";
/**
 * @title Legal Lazy Scheduler
 * @author Marco Oesch <marco.oesch@crea-soft.ch>
 * @notice A generic implementation of a best effort scheduler calling a predefined function in an interval.
 */
contract LegalLazyScheduler is Ownable {
    uint64 public lastUpdate;
    uint64 public intervalDuration;
    bool schedulerEnabled = false;
    function() internal callback;

    event LogRegisteredInterval(uint64 date, uint64 duration);
    event LogProcessedInterval(uint64 date, uint64 intervals);    
    /**
    * Triggers the registered callback function for the number of periods passed since last update
    */
    modifier intervalTrigger() {
        uint64 currentTime = uint64(now);
        uint64 requiredIntervals = (currentTime - lastUpdate) / intervalDuration;
        if( schedulerEnabled && (requiredIntervals > 0)) {
            LogProcessedInterval(lastUpdate, requiredIntervals);
            while (requiredIntervals-- > 0) {
                callback();
            }
            lastUpdate = currentTime;
        }
        _;
    }
    
    function LegalLazyScheduler() {
        lastUpdate = uint64(now);
    }

    function enableScheduler() onlyOwner public {
        schedulerEnabled = true;
    }

    function registerIntervalCall(uint64 _intervalDuration, function() internal _callback) internal {
        lastUpdate = uint64(now);
        intervalDuration = _intervalDuration;
        callback = _callback;
        LogRegisteredInterval(lastUpdate, intervalDuration);        
    }
}