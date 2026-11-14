// Prints each replica-set member, its role and health
rs.status().members.forEach(m => print("  " + m.name + "   " + m.stateStr.padEnd(10) + " health=" + m.health));
